`timescale 1ns / 1ps

// =============================================================================
// UART + FIFO Loopback 테스트 케이스 UF-01 ~ UF-08
//   DUT : uart_fifo_loopback (uart_rx -> FIFO_RX -> FIFO_TX -> uart_tx)
//   PC 역할의 send_byte 로 rx 에 프레임을 넣고, tx 에서 돌아오는 프레임을
//   monitor 가 비트 중앙에서 읽어 기대값과 비교한다.
//   UF-06 은 UL-08 (UART 단독) 과 같은 자극이라 결과를 직접 비교할 수 있다.
//   파형에서는 tc_no (decimal) 를 추가하면 현재 실행 중인 TC 를 알 수 있다.
// =============================================================================
module tb_uart_fifo_tc;

    parameter BIT = 104160;  // 9600bps 1비트 [ns] = 651 * 16 * 10ns

    reg clk, rst, rx;
    wire tx;

    uart_fifo_loopback dut (
        .clk(clk),
        .rst(rst),
        .rx (rx),
        .tx (tx)
    );

    always #5 clk = ~clk;  // 100MHz

    // DUT 내부 신호 (hierarchical 참조)
    wire       rx_done = dut.w_rx_done;
    wire [7:0] rx_data = dut.w_rx_data;
    wire frx_empty = dut.w_fifo_rx_empty;
    wire ftx_empty = dut.w_fifo_tx_empty;
    wire ftx_full = dut.w_fifo_tx_full;
    wire frx_full = dut.U_FIFO_RX.full;
    wire [1:0] frx_w = dut.U_FIFO_RX.U_CONTROL_UNIT.wptr_reg;
    wire [1:0] frx_r = dut.U_FIFO_RX.U_CONTROL_UNIT.rptr_reg;
    wire [1:0] ftx_w = dut.U_FIFO_TX.U_CONTROL_UNIT.wptr_reg;
    wire [1:0] ftx_r = dut.U_FIFO_TX.U_CONTROL_UNIT.rptr_reg;

    // ------------------------------------------------------------------ 판정
    integer tc_no, tc_fail, tcs_pass, tcs_fail;

    task tc_begin(input integer n, input [8*80-1:0] title);
        begin
            tc_no   = n;
            tc_fail = 0;
            $display("[%0d ns] UF-%02d start : %0s", $time, n, title);
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
                $display("[%0d ns] UF-%02d [PASS]", $time, tc_no);
            end else begin
                tcs_fail = tcs_fail + 1;
                $display("[%0d ns] UF-%02d [FAIL] (%0d item)", $time, tc_no, tc_fail);
            end
        end
    endtask

    // ------------------------------------------------------- PC 역할: rx 송신
    time snd_t0;
    integer sent_total;
    task send_byte(input [7:0] d, input integer bitw);
        integer i;
        begin
            snd_t0 = $time;
            sent_total = sent_total + 1;
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
    time rcv_t[0:511];
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

    // ------------------------------------- monitor 3: FIFO 점유 개수 최대값
    integer occ_rx, occ_tx, max_occ_rx, max_occ_tx;
    always @(posedge clk) begin
        occ_rx = dut.U_FIFO_RX.U_CONTROL_UNIT.full_reg ? 4 : ((frx_w - frx_r) & 3);
        occ_tx = dut.U_FIFO_TX.U_CONTROL_UNIT.full_reg ? 4 : ((ftx_w - ftx_r) & 3);
        if (occ_rx > max_occ_rx) max_occ_rx = occ_rx;
        if (occ_tx > max_occ_tx) max_occ_tx = occ_tx;
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

    task settle(input integer nbit);
        begin
            #(nbit * BIT);
        end
    endtask

    // -------------------------------------------------------------- 시나리오
    integer b_r, b_d, k;
    reg [7:0] corner[0:5];

    initial begin
        clk = 0;
        rst = 1;
        rx = 1;
        tcs_pass = 0;
        tcs_fail = 0;
        tc_no = 0;
        tc_fail = 0;
        sent_total = 0;
        max_occ_rx = 0;
        max_occ_tx = 0;
        corner[0] = 8'h00;
        corner[1] = 8'hFF;
        corner[2] = 8'h55;
        corner[3] = 8'hAA;
        corner[4] = 8'h01;
        corner[5] = 8'h80;
        #100 rst = 0;
        #2000;

        // ---- UF-01 : 리셋 직후 상태
        tc_begin(1, "reset state (tx idle, both FIFOs empty)");
        check(tx === 1'b1, "tx must be 1 (idle) after reset");
        check(frx_empty === 1'b1 && frx_full === 1'b0, "FIFO_RX: empty=1 full=0");
        check(ftx_empty === 1'b1 && ftx_full === 1'b0, "FIFO_TX: empty=1 full=0");
        check(rcv_n == 0 && done_n == 0, "no frame / pulse before any rx input");
        tc_end;

        // ---- UF-02 : 0x30 프레임 형식
        tc_begin(2, "0x30 echo frame format on tx");
        b_r = rcv_n;
        b_d = done_n;
        send_byte(8'h30, BIT);
        wait_rcv(b_r + 1);
        check(rcv_n == b_r + 1, "exactly one echo frame on tx");
        check(rcv_start[b_r] === 1'b0, "START bit must be 0");
        check(rcv_data[b_r] === 8'h30, "D0..D7 must be 0x30 (0,0,0,0,1,1,0,0 LSB first)");
        check(rcv_stop[b_r] === 1'b1, "STOP bit must be 1");
        check(done_data[b_d] === 8'h30, "rx_data at rx_done must be 0x30");
        check(done_n == b_d + 1, "rx_done pulses exactly once");
        tc_end;

        // ---- UF-03 : FIFO 를 거치는 지연 (UL-03 은 20ns)
        tc_begin(3, "latency rx_done -> tx START through 2 FIFOs");
        check((rcv_t[b_r] - done_t[b_d]) <= 50, "tx START within 5 clock after rx_done");
        check(rcv_t[b_r] > done_t[b_d], "tx START must come after rx_done");
        $display("    info: rx_done -> tx START = %0d ns (UART only: 20 ns)", rcv_t[b_r] - done_t[b_d]);
        tc_end;

        // ---- UF-04 : 경계값 데이터 echo
        tc_begin(4, "corner data echo 00 FF 55 AA 01 80");
        for (k = 0; k < 6; k = k + 1) begin
            b_r = rcv_n;
            send_byte(corner[k], BIT);
            wait_rcv(b_r + 1);
            check(rcv_data[b_r] === corner[k], "echo byte must equal sent byte");
            if (rcv_data[b_r] !== corner[k]) $display("    sent %h, echo %h", corner[k], rcv_data[b_r]);
            settle(1);
        end
        tc_end;

        // ---- UF-05 : 정상 속도 연속 송신 8 바이트
        tc_begin(5, "back-to-back 8 bytes (0x41..0x48) at 9600bps");
        b_r = rcv_n;
        for (k = 0; k < 8; k = k + 1) send_byte(8'h41 + k, BIT);
        wait_rcv(b_r + 8);
        check(rcv_n - b_r == 8, "8 echo frames expected");
        for (k = 0; k < 8; k = k + 1) begin
            check(rcv_data[b_r+k] === (8'h41 + k), "echo order and value must match");
            if (rcv_data[b_r+k] !== (8'h41 + k)) $display("    #%0d sent %h, echo %h", k, 8'h41 + k, rcv_data[b_r+k]);
        end
        settle(2);
        tc_end;

        // ---- UF-06 : 송신 +2% 빠른 연속 송신 20 바이트 (UL-08 과 같은 자극)
        tc_begin(6, "20 bytes, sender +2% fast: no byte lost (UL-08: 10 of 20)");
        b_r = rcv_n;
        b_d = done_n;
        for (k = 0; k < 20; k = k + 1) send_byte(8'h41 + k, BIT * 98 / 100);
        wait_rcv(b_r + 20);
        settle(2);
        check(done_n - b_d == 20, "uart_rx must receive all 20 bytes");
        check(rcv_n - b_r == 20, "all 20 bytes must be echoed (no loss)");
        for (k = 0; k < 20; k = k + 1) begin
            check(rcv_data[b_r+k] === (8'h41 + k), "echo order and value must match");
            if (rcv_data[b_r+k] !== (8'h41 + k)) $display("    #%0d sent %h, echo %h", k, 8'h41 + k, rcv_data[b_r+k]);
        end
        $display("    info: sent 20, rx_done %0d, echoed %0d (UART only: echoed 10)", done_n - b_d, rcv_n - b_r);
        tc_end;

        // ---- UF-07 : 송신 +4% 빠른 연속 송신 40 바이트 -> FIFO_TX 에 실제로 쌓임
        tc_begin(7, "40 bytes, sender +4% fast: FIFO_TX buffers, no loss");
        b_r = rcv_n;
        b_d = done_n;
        max_occ_tx = 0;
        max_occ_rx = 0;
        for (k = 0; k < 40; k = k + 1) send_byte(8'h80 + k, BIT * 96 / 100);
        wait_rcv(b_r + 40);
        settle(2);
        check(done_n - b_d == 40, "uart_rx must receive all 40 bytes");
        check(rcv_n - b_r == 40, "all 40 bytes must be echoed (no loss)");
        for (k = 0; k < 40; k = k + 1) begin
            check(rcv_data[b_r+k] === (8'h80 + k), "echo order and value must match");
            if (rcv_data[b_r+k] !== (8'h80 + k)) $display("    #%0d sent %h, echo %h", k, 8'h80 + k, rcv_data[b_r+k]);
        end
        check(max_occ_tx >= 2, "FIFO_TX must hold 2 or more bytes at some point");
        $display("    info: sent 40, echoed %0d, max occupancy FIFO_RX %0d, FIFO_TX %0d", rcv_n - b_r, max_occ_rx, max_occ_tx);
        tc_end;

        // ---- UF-08 : 전체 종료 후 상태 (데이터 잔류·중복 없음)
        tc_begin(8, "after all frames: FIFOs empty, echoed count == sent count");
        settle(5);
        check(frx_empty === 1'b1, "FIFO_RX must be empty");
        check(ftx_empty === 1'b1, "FIFO_TX must be empty");
        check(rcv_n == sent_total, "total echoed frames must equal total sent frames");
        check(tx === 1'b1, "tx must be back to idle");
        $display("    info: total sent %0d, total echoed %0d", sent_total, rcv_n);
        tc_end;

        // ---- 요약
        $display("====================================================");
        $display("SUMMARY (uart_fifo_loopback) : TC PASS %0d, TC FAIL %0d", tcs_pass, tcs_fail);
        $display("====================================================");
        $finish;
    end

endmodule