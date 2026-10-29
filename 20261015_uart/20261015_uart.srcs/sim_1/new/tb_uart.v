`timescale 1ns / 1ps

module tb_uart ();

    // bit period
    // 1 clock = 10ns → total period
    parameter BAUD_BIT_PERIOD = (100_000_000 / 9600) * 10;

    reg clk, rst, rx;
    reg [7:0] result_data, expected_data;  // TX & RX 결과 비교용 데이터
    wire tx;
    wire fnd_com, fnd_font;
    integer i;
    integer pass_count, fail_count;

    uart_fifo_ascii DUT (
        .clk(clk),
        .rst(rst),
        .rx (rx),
        .tx (tx),
        .fnd_com(fnd_com),
        .fnd_font(fnd_font)
    );

    // Clock generation
    always #5 clk = ~clk;

    // for UART rx, like PC
    task sender_uart(input [7:0] send_data);
        integer i;
        begin
            rx = 0;  // go to start bit
            #(BAUD_BIT_PERIOD);
            // Check start bit 0

            // Data bit check
            for (i = 0; i < 8; i = i + 1) begin
                rx = send_data[i];
                #(BAUD_BIT_PERIOD);
            end

            rx = 1;  // stop bit
            #(BAUD_BIT_PERIOD);
        end
    endtask

    // RX
    task receive_uart(output [7:0] rx_data);
        integer i;
        begin
            // Stop bit check
            wait (~tx);  // module 출력 신호 그대로 받음
            #(BAUD_BIT_PERIOD / 2);  // START 내에서 1/2만 진행
            // Check start bit 0
            if (tx != 0) $display("Error start bit");

            // Data bit check
            for (i = 0; i < 8; i = i + 1) begin
                #(BAUD_BIT_PERIOD);
                rx_data[i] = tx;  // rx: 0, 1 data
            end

            #(BAUD_BIT_PERIOD);

            // Stop bit check
            if (!tx) $display("Error stop bit");

            // 더 시간 보낼 것이 없음
        end
    endtask

    task score_board(input [7:0] result, expected);
        begin 
            // Compare result data with expected data
            if (result == expected_data) begin  // 8'h30: btn press 시 얻는 데이터
                pass_count = pass_count + 1;
                $display("%t : PASS!!!", $time);
            end else begin 
                fail_count = fail_count + 1;
                $display("%t : Fail...", $time);
            end
        end 

    endtask

    // TX & RX
    initial begin
        clk = 0;
        rst = 1;
        rx = 1;
        i = 0;
        pass_count = 0;
        fail_count = 0;
        expected_data = 8'h30;
        #10 rst = 0;

        // for loop
        for (i = 0; i < 256; i= i +1) begin
            // Generate random expected data, using modulo calculation
            expected_data = $random() % 256;
            $display("Expected Data : ", expected_data);

            sender_uart(expected_data);
            // UART Receive
            receive_uart(result_data);
            score_board(result_data, expected_data);
        end
        #1000;
        $display("Total Test Num = %d", i);
        $display("Pass Count = %d", pass_count);
        $display("Fail Count = %d", fail_count);
        $stop;
    end

endmodule
