`timescale 1ns / 1ps

// =============================================================================
// UART Loopback 테스트 케이스 UL-01 ~ UL-08
//   DUT : uart_loopback (uart_rx + uart_tx + baud_tick_gen)
//   PC 역할의 send_byte 로 rx 에 프레임을 넣고, tx 에서 돌아오는 프레임을
//   monitor 가 비트 중앙에서 읽어 기대값과 비교한다.
//   콘솔에 TC 별 [PASS]/[FAIL] 과 마지막에 SUMMARY 를 출력한다.
//   파형에서는 tc_no (decimal) 를 추가하면 현재 실행 중인 TC 를 알 수 있다.
// =============================================================================
module tb_uart_loopback_tc;

    parameter BIT = 104160;  // 9600bps 1비트 [ns] = 651 * 16 * 10ns

    reg clk, rst, rx;
    wire tx, rx_done;
    wire [7:0] rx_data;

    uart_loopback dut (
        .clk    (clk),
        .rst    (rst),
        .rx     (rx),
        .tx     (tx),
        .rx_done(rx_done),
        .rx_data(rx_data)
    );

    always #5 clk = ~clk;  // 100MHz

    // ------------------------------------------------------------------ 판정
    integer tc_no;  // 파형 확인용: 현재 TC 번호
    integer tc_fail;  // 현재 TC 의 실패 항목 수
    integer tcs_pass, tcs_fail;

    task tc_begin(input integer n, input [8*80-1:0] title);
        begin
            tc_no   = n;
            tc_fail = 0;
            $display("[%0d ns] UL-%02d start : %0s", $time, n, title);
        end
    endtask

    task check(input cond, input [8*80-1:0] msg);
        begin
            if (!cond) begin
                tc_fail = tc_fail + 1;
                $display("    [FAIL] %0s", msg);
            end
        end
    endtask

    task tc_end;
        begin
            if (tc_fail == 0) begin
                tcs_pass = tcs_pass + 1;
                $display("[%0d ns] UL-%02d [PASS]", $time, tc_no);
            end else begin
                tcs_fail = tcs_fail + 1;
                $display("[%0d ns] UL-%02d [FAIL] (%0d item)", $time, tc_no, tc_fail);
            end
        end
    endtask

    // ------------------------------------------------------- PC 역할: rx 송신
    time snd_t0;  // 마지막 send_byte 의 START 하강 시각
    task send_byte(input [7:0] d, input integer bitw);
        integer i;
        begin
            snd_t0 = $time;
            rx = 1'b0;
            #(bitw);  // START
            for (i = 0; i < 8; i = i + 1) begin
                rx = d[i];  // LSB 먼저
                #(bitw);
            end
            rx = 1'b1;
            #(bitw);  // STOP
        end
    endtask

    // ------------------------------------- monitor 1: tx 프레임을 비트 중앙에서 읽음
    reg [7:0] rcv_data[0:511];
    reg rcv_start[0:511];
    reg rcv_stop[0:511];
    time rcv_t[0:511];  // START 하강 시각
    integer rcv_n;
    reg [7:0] mr;
    integer mj;
    initial begin
        rcv_n = 0;
        forever begin
            @(negedge tx);
            rcv_t[rcv_n] = $time;
            #(BIT / 2);
            rcv_start[rcv_n] = tx;
            for (mj = 0; mj < 8; mj = mj + 1) begin
                #(BIT);
                mr[mj] = tx;
            end
            rcv_data[rcv_n] = mr;
            #(BIT);
            rcv_stop[rcv_n] = tx;
            rcv_n = rcv_n + 1;
        end
    end

    // ------------------------------------- monitor 2: rx_done 펄스 시각·폭·데이터
    reg [7:0] done_data[0:511];
    time done_t[0:511];
    time done_w[0:511];
    integer done_n;
    initial begin
        done_n = 0;
        forever begin
            @(posedge rx_done);
            done_t[done_n]    = $time;
            done_data[done_n] = rx_data;
            @(negedge rx_done);
            done_w[done_n] = $time - done_t[done_n];
            done_n = done_n + 1;
        end
    end

    // ------------------------------------------------------------ 보조 task
    integer wt;
    task wait_rcv(input integer n);  // echo 프레임이 n 개가 될 때까지 (최대 40비트)
        begin
            wt = 0;
            while (rcv_n < n && wt < 40 * BIT) begin
                #(1000);
                wt = wt + 1000;
            end
        end
    endtask

    task settle(input integer nbit);  // 라인이 조용해질 때까지 대기
        begin
            #(nbit * BIT);
        end
    endtask

    // -------------------------------------------------------------- 시나리오
    integer b_r, b_d, k, t_02;
    reg [7:0] corner[0:5];
    reg [7:0] pat[0:3];

    initial begin
        clk = 0;
        rst = 1;
        rx = 1;
        tcs_pass = 0;
        tcs_fail = 0;
        tc_no = 0;
        tc_fail = 0;
        corner[0] = 8'h00;
        corner[1] = 8'hFF;
        corner[2] = 8'h55;
        corner[3] = 8'hAA;
        corner[4] = 8'h01;
        corner[5] = 8'h80;
        #100 rst = 0;
        #2000;

        // ---- UL-01 : 리셋 직후 상태
        tc_begin(1, "reset state (tx idle high, rx_done low)");
        check(tx === 1'b1, "tx must be 1 (idle) after reset");
        check(rx_done === 1'b0, "rx_done must be 0 after reset");
        check(rcv_n == 0 && done_n == 0, "no frame / pulse before any rx input");
        tc_end;

        // ---- UL-02 : 0x30 프레임 형식 (START 0, D0..D7 LSB 먼저, STOP 1)
        tc_begin(2, "0x30 echo frame format on tx");
        b_r = rcv_n;
        b_d = done_n;
        send_byte(8'h30, BIT);
        t_02 = snd_t0;
        wait_rcv(b_r + 1);
        check(rcv_n == b_r + 1, "exactly one echo frame on tx");
        check(rcv_start[b_r] === 1'b0, "START bit must be 0");
        check(rcv_data[b_r] === 8'h30, "D0..D7 must be 0x30 (0,0,0,0,1,1,0,0 LSB first)");
        check(rcv_stop[b_r] === 1'b1, "STOP bit must be 1");
        check(done_data[b_d] === 8'h30, "rx_data at rx_done must be 0x30");
        tc_end;

        // ---- UL-03 : rx_done 타이밍과 폭 (UL-02 의 0x30 프레임으로 측정)
        tc_begin(3, "rx_done timing and width (measured on UL-02 frame)");
        check(done_n == b_d + 1, "rx_done pulses exactly once per frame");
        check((done_t[b_d] - t_02) > 9 * BIT, "rx_done not earlier than 9.0 bit after START");
        check((done_t[b_d] - t_02) < 10 * BIT, "rx_done not later than 10.0 bit after START");
        check(done_w[b_d] == 10, "rx_done width must be 1 clock (10ns)");
        $display("    info: rx_done at %0d ns after START (%0d.%03d bit), width %0d ns",
                 done_t[b_d] - t_02, (done_t[b_d] - t_02) / BIT, ((done_t[b_d] - t_02) % BIT) * 1000 / BIT,
                 done_w[b_d]);
        check((rcv_t[b_r] - done_t[b_d]) <= 50, "tx START within 5 clock after rx_done");
        $display("    info: rx_done -> tx START = %0d ns", rcv_t[b_r] - done_t[b_d]);
        tc_end;

        // ---- UL-04 : 경계값 데이터 echo
        tc_begin(4, "corner data echo 00 FF 55 AA 01 80");
        for (k = 0; k < 6; k = k + 1) begin
            b_r = rcv_n;
            b_d = done_n;
            send_byte(corner[k], BIT);
            wait_rcv(b_r + 1);
            check(rcv_data[b_r] === corner[k], "echo byte must equal sent byte");
            check(done_data[b_d] === corner[k], "rx_data must equal sent byte");
            if (rcv_data[b_r] !== corner[k])
                $display("    sent %h, echo %h", corner[k], rcv_data[b_r]);
            settle(1);
        end
        tc_end;

        // ---- UL-05 : 정상 속도 연속 송신 (바이트 사이 간격 0) 8 바이트
        tc_begin(5, "back-to-back 8 bytes (0x41..0x48) at 9600bps");
        b_r = rcv_n;
        b_d = done_n;
        for (k = 0; k < 8; k = k + 1) send_byte(8'h41 + k, BIT);
        wait_rcv(b_r + 8);
        check(rcv_n - b_r == 8, "8 echo frames expected");
        for (k = 0; k < 8; k = k + 1) begin
            check(rcv_data[b_r+k] === (8'h41 + k), "echo order and value must match");
            if (rcv_data[b_r+k] !== (8'h41 + k))
                $display("    #%0d sent %h, echo %h", k, 8'h41 + k, rcv_data[b_r+k]);
        end
        settle(2);
        tc_end;

        // ---- UL-06 : 송신 비트 폭 오차 -4% / +4% 허용
        tc_begin(6, "bit width error -4% / +4% still received correctly");
        pat[0] = 8'h5A;
        pat[1] = 8'hA5;
        for (k = 0; k < 2; k = k + 1) begin
            b_r = rcv_n;
            send_byte(pat[k], BIT * 96 / 100);
            wait_rcv(b_r + 1);
            check(rcv_data[b_r] === pat[k], "-4% sender: echo must equal sent byte");
            settle(2);
            b_r = rcv_n;
            send_byte(pat[k], BIT * 104 / 100);
            wait_rcv(b_r + 1);
            check(rcv_data[b_r] === pat[k], "+4% sender: echo must equal sent byte");
            settle(2);
        end
        tc_end;

        // ---- UL-07 : 비트 폭 오차 초과 / Baud 불일치 -> 잘못 수신되는지 확인 (슬라이드 6)
        tc_begin(7, "baud mismatch: wrong data expected (-8%, +8%, 4800bps)");
        pat[0] = 8'h55;
        pat[1] = 8'hAA;
        for (k = 0; k < 2; k = k + 1) begin
            b_d = done_n;
            send_byte(pat[k], BIT * 92 / 100);
            settle(30);
            check(done_n > b_d && done_data[b_d] !== pat[k], "-8% sender must be received wrong");
            $display("    -8%%: sent %h, rx_data %h", pat[k], done_data[b_d]);
            b_d = done_n;
            send_byte(pat[k], BIT * 108 / 100);
            settle(30);
            check(done_n > b_d && done_data[b_d] !== pat[k], "+8% sender must be received wrong");
            $display("    +8%%: sent %h, rx_data %h", pat[k], done_data[b_d]);
        end
        // 송신 4800bps (비트 폭 2배), 수신 9600bps : 슬라이드 6 의 불일치 그림
        b_d = done_n;
        send_byte(8'h30, 2 * BIT);
        settle(60);
        check(done_n > b_d, "rx_done must still occur");
        check(done_data[b_d] === 8'h00, "4800bps sender: rx_data must be 0x00 (slide 6)");
        $display("    4800bps sender: sent 30, rx_data %h", done_data[b_d]);
        tc_end;

        // ---- UL-08 : 송신이 2% 빠른 연속 송신 20 바이트 (한계 확인, FIFO 필요성)
        tc_begin(8, "limit: 20 bytes, sender +2% fast, echo loses bytes");
        b_r = rcv_n;
        b_d = done_n;
        for (k = 0; k < 20; k = k + 1) send_byte(8'h41 + k, BIT * 98 / 100);
        settle(30);
        check(done_n - b_d == 20, "uart_rx must receive all 20 bytes (rx_done x20)");
        check(rcv_n - b_r < 20, "echo count < 20 (tx_start ignored while uart_tx busy)");
        $display("    info: sent 20, rx_done %0d, echoed %0d", done_n - b_d, rcv_n - b_r);
        tc_end;

        // ---- 요약
        $display("====================================================");
        $display("SUMMARY (uart_loopback) : TC PASS %0d, TC FAIL %0d", tcs_pass, tcs_fail);
        $display("====================================================");
        $finish;
    end

endmodule