`timescale 1ns / 1ps

// =============================================================================
// FIFO 테스트 케이스 FF-01 ~ FF-13
//   DUT : fifo (DEPTH = 4, 8bit)  -- 입력은 negedge 에 바꾸고 posedge 에 DUT 가 읽는다.
//   기준 모델(큐) 을 함께 돌려 매 negedge 마다 full / empty / popdata 를 비교하고(scoreboard),
//   TC 별로는 의도한 동작(포인터, 무시되는 push/pop 등)을 직접 확인한다.
//   파형에서는 tc_no (decimal) 를 추가하면 현재 실행 중인 TC 를 알 수 있다.
// =============================================================================
module tb_fifo_tc;

    parameter DEPTH = 4;

    reg clk, rst, push, pop;
    reg  [7:0] pushdata;
    wire [7:0] popdata;
    wire full, empty;

    fifo #(
        .DEPTH(DEPTH)
    ) dut (
        .clk     (clk),
        .rst     (rst),
        .push    (push),
        .pop     (pop),
        .pushdata(pushdata),
        .popdata (popdata),
        .full    (full),
        .empty   (empty)
    );

    always #5 clk = ~clk;  // 100MHz

    // 내부 포인터 (hierarchical 참조)
    wire [1:0] wptr = dut.U_CONTROL_UNIT.wptr_reg;
    wire [1:0] rptr = dut.U_CONTROL_UNIT.rptr_reg;

    // ------------------------------------------------------------------ 판정
    integer tc_no, tc_fail, tcs_pass, tcs_fail;
    integer sb_err, sb_err_at_begin;

    task tc_begin(input integer n, input [8*80-1:0] title);
        begin
            tc_no = n;
            tc_fail = 0;
            sb_err_at_begin = sb_err;
            $display("[%0d ns] FF-%02d start : %0s", $time, n, title);
        end
    endtask

    task check(input cond, input [8*80-1:0] msg);
        begin
            if (!cond) begin
                tc_fail = tc_fail + 1;
                $display("    [FAIL] %0s  (time %0d ns)", msg, $time);
            end
        end
    endtask

    task tc_end;
        integer e;
        begin
            e = sb_err - sb_err_at_begin;  // 이 TC 동안 scoreboard 가 잡은 불일치
            if (e != 0) tc_fail = tc_fail + e;
            if (tc_fail == 0) begin
                tcs_pass = tcs_pass + 1;
                $display("[%0d ns] FF-%02d [PASS]", $time, tc_no);
            end else begin
                tcs_fail = tcs_fail + 1;
                $display("[%0d ns] FF-%02d [FAIL] (%0d item, scoreboard %0d)", $time, tc_no, tc_fail, e);
            end
        end
    endtask

    // ------------------------------------------------- 기준 모델 (큐) + scoreboard
    reg [7:0] mq[0:4095];
    integer mh, mt, mcnt;  // head, tail, count
    integer do_push_m, do_pop_m;
    reg sb_on;

    // posedge 에서 입력(안정) 을 읽어 모델 갱신: push 는 가득 차지 않았을 때, pop 은 비어 있지 않을 때만 동작
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            mh = 0;
            mt = 0;
            mcnt = 0;
        end else begin
            do_push_m = (push && mcnt < DEPTH) ? 1 : 0;
            do_pop_m  = (pop && mcnt > 0) ? 1 : 0;
            if (do_push_m) begin
                mq[mt] = pushdata;
                mt = mt + 1;
            end
            if (do_pop_m) mh = mh + 1;
            mcnt = mcnt + do_push_m - do_pop_m;
        end
    end

    // negedge 마다 DUT 출력과 모델 비교
    always @(negedge clk) begin
        if (sb_on) begin
            if (full !== (mcnt == DEPTH)) begin
                sb_err = sb_err + 1;
                $display("    [SB] full mismatch at %0d ns : dut %b, model count %0d", $time, full, mcnt);
            end
            if (empty !== (mcnt == 0)) begin
                sb_err = sb_err + 1;
                $display("    [SB] empty mismatch at %0d ns : dut %b, model count %0d", $time, empty, mcnt);
            end
            if (mcnt > 0 && popdata !== mq[mh]) begin
                sb_err = sb_err + 1;
                $display("    [SB] popdata mismatch at %0d ns : dut %h, model %h", $time, popdata, mq[mh]);
            end
        end
    end

    // ------------------------------------------------------------ 보조 task
    // 입력을 걸고 다음 negedge 까지 진행한다 (사이의 posedge 에서 DUT 가 입력을 읽음)
    task step(input p, input q, input [7:0] d);
        begin
            push = p;
            pop = q;
            pushdata = d;
            @(negedge clk);
        end
    endtask

    task idle;
        begin
            step(0, 0, 8'h00);
        end
    endtask

    // ------------------------------------------------ 커버리지 (랜덤 TC 용)
    integer cov_full, cov_empty, cov_push, cov_pop, cov_both;
    always @(negedge clk)
        if (sb_on) begin
            if (full) cov_full = cov_full + 1;
            if (empty) cov_empty = cov_empty + 1;
        end

    // -------------------------------------------------------------- 시나리오
    integer i;
    reg [7:0] rnd;

    initial begin
        clk = 0;
        rst = 1;
        push = 0;
        pop = 0;
        pushdata = 0;
        sb_on = 0;
        sb_err = 0;
        tc_no = 0;
        tc_fail = 0;
        tcs_pass = 0;
        tcs_fail = 0;
        cov_full = 0;
        cov_empty = 0;
        cov_push = 0;
        cov_pop = 0;
        cov_both = 0;
        mh = 0;
        mt = 0;
        mcnt = 0;

        @(negedge clk);
        @(negedge clk);
        rst = 0;
        @(negedge clk);
        sb_on = 1;

        // ---- FF-01 : 리셋 상태
        tc_begin(1, "reset state: full=0 empty=1 wptr=rptr=0");
        idle;
        check(full === 1'b0, "full must be 0");
        check(empty === 1'b1, "empty must be 1");
        check(wptr === 2'd0 && rptr === 2'd0, "wptr, rptr must be 0");
        tc_end;

        // ---- FF-02 : push 1 개
        tc_begin(2, "push 1 item (0x0A): empty released, wptr+1");
        step(1, 0, 8'h0A);
        check(empty === 1'b0, "empty must be 0 after first push");
        check(full === 1'b0, "full must stay 0");
        check(wptr === 2'd1 && rptr === 2'd0, "wptr must be 1, rptr 0");
        check(popdata === 8'h0A, "popdata (front) must be 0x0A");
        tc_end;

        // ---- FF-03 : 가득 찰 때까지 push (4 개)
        tc_begin(3, "push 0B 0C 0D : full=1 after 4th, wptr wraps to 0");
        step(1, 0, 8'h0B);
        step(1, 0, 8'h0C);
        check(full === 1'b0, "full must be 0 with 3 items");
        step(1, 0, 8'h0D);
        check(full === 1'b1, "full must be 1 with 4 items");
        check(empty === 1'b0, "empty must be 0");
        check(wptr === 2'd0, "wptr must wrap to 0");
        tc_end;

        // ---- FF-04 : full 에서 push -> 무시
        tc_begin(4, "overflow: push 0x0E while full is ignored");
        step(1, 0, 8'h0E);
        step(1, 0, 8'h0F);
        check(full === 1'b1, "full must stay 1");
        check(wptr === 2'd0 && rptr === 2'd0, "pointers must not move");
        check(popdata === 8'h0A, "front data must still be 0x0A");
        step(0, 0, 8'h00);
        tc_end;

        // ---- FF-05 : pop 순서 = push 순서
        tc_begin(5, "pop order equals push order: 0A 0B 0C 0D");
        check(popdata === 8'h0A, "1st pop data must be 0x0A");
        step(0, 1, 8'h00);
        check(full === 1'b0, "full must be released by first pop");
        check(popdata === 8'h0B, "2nd pop data must be 0x0B");
        step(0, 1, 8'h00);
        check(popdata === 8'h0C, "3rd pop data must be 0x0C");
        step(0, 1, 8'h00);
        check(popdata === 8'h0D, "4th pop data must be 0x0D (0E, 0F were not stored)");
        step(0, 1, 8'h00);
        tc_end;

        // ---- FF-06 : 모두 꺼내면 empty
        tc_begin(6, "empty after popping all, rptr == wptr");
        check(empty === 1'b1, "empty must be 1");
        check(full === 1'b0, "full must be 0");
        check(rptr === wptr, "rptr must equal wptr");
        tc_end;

        // ---- FF-07 : empty 에서 pop -> 무시
        tc_begin(7, "underflow: pop while empty is ignored");
        step(0, 1, 8'h00);
        step(0, 1, 8'h00);
        check(empty === 1'b1, "empty must stay 1");
        check(rptr === wptr, "rptr must not run past wptr");
        step(1, 0, 8'h77);
        check(popdata === 8'h77, "data pushed after underflow must be intact (0x77)");
        step(0, 1, 8'h00);
        check(empty === 1'b1, "empty must be 1 after popping 0x77");
        tc_end;

        // ---- FF-08 : 포인터 되돌림 (여러 바퀴)
        tc_begin(8, "pointer wrap-around: 12 push/pop pairs, order kept");
        step(1, 0, 8'h10);
        step(1, 0, 8'h11);
        for (i = 0; i < 12; i = i + 1) begin
            step(1, 0, 8'h12 + i);
            check(popdata === (8'h10 + i), "front data must follow push order");
            step(0, 1, 8'h00);
        end
        check(popdata === 8'h1C, "front must be 0x1C (2 items left: 1C 1D)");
        step(0, 1, 8'h00);
        check(popdata === 8'h1D, "last data must be 0x1D");
        step(0, 1, 8'h00);
        check(empty === 1'b1, "empty must be 1 at end");
        tc_end;

        // ---- FF-09 : 중간 상태에서 동시 push·pop
        tc_begin(9, "simultaneous push+pop with 2 items: count and order kept");
        step(1, 0, 8'hA1);
        step(1, 0, 8'hA2);
        for (i = 0; i < 6; i = i + 1) begin
            check(popdata === (8'hA1 + i), "popped data must be the oldest");
            step(1, 1, 8'hA3 + i);
            check(full === 1'b0 && empty === 1'b0, "count stays 2: neither full nor empty");
        end
        check(popdata === 8'hA7, "front must be 0xA7");
        step(0, 1, 8'h00);
        check(popdata === 8'hA8, "last must be 0xA8");
        step(0, 1, 8'h00);
        check(empty === 1'b1, "empty at end");
        tc_end;

        // ---- FF-10 : full 에서 동시 push·pop -> pop 만 수행
        tc_begin(10, "simultaneous push+pop while full: only pop executes");
        step(1, 0, 8'hB1);
        step(1, 0, 8'hB2);
        step(1, 0, 8'hB3);
        step(1, 0, 8'hB4);
        check(full === 1'b1, "precondition: full");
        step(1, 1, 8'hEE);
        check(full === 1'b0, "full must be released (pop executed)");
        check(empty === 1'b0, "empty must be 0");
        check(popdata === 8'hB2, "front must be 0xB2 (B1 popped)");
        step(0, 1, 8'h00);
        check(popdata === 8'hB3, "next must be 0xB3 (0xEE was not stored)");
        step(0, 1, 8'h00);
        check(popdata === 8'hB4, "next must be 0xB4");
        step(0, 1, 8'h00);
        check(empty === 1'b1, "empty must be 1: 0xEE is lost by design");
        tc_end;

        // ---- FF-11 : empty 에서 동시 push·pop -> push 만 수행
        tc_begin(11, "simultaneous push+pop while empty: only push executes");
        check(empty === 1'b1, "precondition: empty");
        step(1, 1, 8'hCC);
        check(empty === 1'b0, "empty must be released (push executed)");
        check(full === 1'b0, "full must be 0");
        check(popdata === 8'hCC, "front must be 0xCC (pop was ignored)");
        step(0, 1, 8'h00);
        check(empty === 1'b1, "empty must be 1 after popping 0xCC");
        tc_end;

        // ---- FF-12 : 데이터가 있는 상태에서 리셋
        tc_begin(12, "reset with data inside: empty=1 full=0 pointers 0");
        step(1, 0, 8'hD1);
        step(1, 0, 8'hD2);
        step(1, 0, 8'hD3);
        step(1, 0, 8'hD4);
        check(full === 1'b1, "precondition: full");
        push = 0;
        sb_on = 0;
        rst = 1;
        #1;
        check(empty === 1'b1 && full === 1'b0, "async reset: empty=1 full=0");
        check(wptr === 2'd0 && rptr === 2'd0, "async reset: wptr=rptr=0");
        @(negedge clk);
        @(negedge clk);
        rst = 0;
        @(negedge clk);
        sb_on = 1;
        step(1, 0, 8'hD5);
        check(popdata === 8'hD5 && empty === 1'b0, "first push after reset works (0xD5)");
        step(0, 1, 8'h00);
        tc_end;

        // ---- FF-13 : 랜덤 push/pop 2000 사이클 vs 기준 모델
        tc_begin(13, "random push/pop 2000 cycles vs reference model");
        cov_full = 0;
        cov_empty = 0;
        for (i = 0; i < 2000; i = i + 1) begin
            rnd = $random;
            step(rnd[0], rnd[1], $random);
            if (push) cov_push = cov_push + 1;
            if (pop) cov_pop = cov_pop + 1;
            if (push && pop) cov_both = cov_both + 1;
        end
        step(0, 0, 8'h00);
        check(cov_full > 0, "random test must reach full at least once");
        check(cov_empty > 0, "random test must reach empty at least once");
        check(cov_both > 0, "random test must hit simultaneous push+pop");
        $display("    info: cycles with push %0d, pop %0d, both %0d; full %0d, empty %0d",
                 cov_push, cov_pop, cov_both, cov_full, cov_empty);
        tc_end;

        // ---- 요약
        $display("====================================================");
        $display("SUMMARY (fifo) : TC PASS %0d, TC FAIL %0d, scoreboard errors %0d", tcs_pass, tcs_fail, sb_err);
        $display("====================================================");
        $finish;
    end

endmodule