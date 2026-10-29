`timescale 1ns / 1ps

// Test Case 1 ~ 8 : FIFO 단독 검증
// 각 Test Case는 clk 상승엣지 직후(#1)의 값을 확인하고,
// pop_data처럼 상승엣지 이전의 값이 필요한 경우는 입력을 넣은 직후(negedge + #1)에 확인한다.
module tb_hw_fifo ();
    parameter DEPTH = 4;

    reg clk, rst, push, pop;
    reg [7:0] push_data;
    wire [7:0] pop_data;
    wire full, empty;

    wire [1:0] wptr = dut.w_wptr;  // FIFO 내부 포인터 (파형 확인용)
    wire [1:0] rptr = dut.w_rptr;

    integer k, i;
    integer tc_fail[1:8];
    integer rand_pop_count;
    reg [1:0] w_b, r_b;  // 상승엣지 이전 포인터 값
    reg [7:0] compare_buffer[0:DEPTH-1];
    reg [1:0] push_count, pop_count;

    fifo #(.DEPTH(DEPTH)) dut (
        .clk(clk),
        .rst(rst),
        .push(push),
        .pop(pop),
        .pushdata(push_data),
        .popdata(pop_data),
        .full(full),
        .empty(empty)
    );

    always #5 clk = ~clk;

    // ok가 X인 경우도 fail로 처리한다. (비교는 ===로 한다)
    task check(input integer tc, input ok);
        begin
            if (ok !== 1'b1) begin
                tc_fail[tc] = tc_fail[tc] + 1;
                $display("%t : [Test Case %0d] fail", $time, tc);
            end
        end
    endtask

    // negedge에 입력을 넣고, 조합회로 출력(pop_data)이 안정되도록 1ns 기다린다.
    task drive(input p, input q, input [7:0] d);
        begin
            @(negedge clk);
            push = p;
            pop = q;
            push_data = d;
            #1;
        end
    endtask

    // 다음 clk 상승엣지가 지난 뒤의 값을 확인하기 위해 기다린다.
    task wait_edge;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    initial begin
        clk = 0;
        rst = 1;
        push = 0;
        pop = 0;
        push_data = 0;
        push_count = 0;
        pop_count = 0;
        rand_pop_count = 0;
        for (i = 1; i <= 8; i = i + 1) tc_fail[i] = 0;

        // ---------------------------------------------------------
        // Test Case 1 : rst = 1 -> Reset, full = 0, empty = 1
        // ---------------------------------------------------------
        @(negedge clk);
        @(negedge clk);
        check(1, full === 1'b0 && empty === 1'b1 && wptr === 2'd0 && rptr === 2'd0);
        rst = 0;
        @(negedge clk);
        @(negedge clk);
        check(1, full === 1'b0 && empty === 1'b1 && wptr === 2'd0 && rptr === 2'd0);

        // ---------------------------------------------------------
        // Test Case 2 : state : empty, push = 1 (0a, 0b, 0c, 0d) -> Store data, full = 1
        // ---------------------------------------------------------
        for (k = 0; k < 4; k = k + 1) begin
            drive(1, 0, 8'h0a + k);
            wait_edge;
            check(2, wptr === ((k + 1) % 4));          // 1, 2, 3, 0
            if (k == 0) check(2, empty === 1'b0);      // 첫 push에서 empty = 0
            if (k < 3) check(2, full === 1'b0);
            else check(2, full === 1'b1);              // 4번째 push에서 full = 1
        end

        // ---------------------------------------------------------
        // Test Case 3 : state : full, push = 1 (0e) -> Ignore push
        // ---------------------------------------------------------
        drive(1, 0, 8'h0e);
        w_b = wptr;
        wait_edge;
        check(3, wptr === w_b && full === 1'b1);       // 0e는 저장되지 않음 (Test Case 4에서 데이터로도 확인)

        // ---------------------------------------------------------
        // Test Case 4 : state : full, pop = 1 (4 times) -> Pop in FIFO order, empty = 1
        // ---------------------------------------------------------
        for (k = 0; k < 4; k = k + 1) begin
            drive(0, 1, 8'h00);
            check(4, pop_data === (8'h0a + k));        // pop 시점의 pop_data : 0a, 0b, 0c, 0d
            wait_edge;
            check(4, rptr === ((k + 1) % 4));          // 1, 2, 3, 0
            if (k == 0) check(4, full === 1'b0);       // 첫 pop에서 full = 0
            if (k < 3) check(4, empty === 1'b0);
            else check(4, empty === 1'b1);             // 4번째 pop에서 empty = 1
        end

        // ---------------------------------------------------------
        // Test Case 5 : state : empty, pop = 1 -> Ignore pop
        // ---------------------------------------------------------
        drive(0, 1, 8'h00);
        r_b = rptr;
        wait_edge;
        check(5, rptr === r_b && empty === 1'b1);

        // ---------------------------------------------------------
        // Test Case 6 : state : empty, push = 1, pop = 1 -> Push only
        // ---------------------------------------------------------
        drive(1, 1, 8'h0f);
        w_b = wptr;
        r_b = rptr;
        wait_edge;
        check(6, wptr === ((w_b + 1) % 4) && rptr === r_b && empty === 1'b0);

        // ---------------------------------------------------------
        // Test Case 7 : state : not full, not empty, push = 1, pop = 1 -> Push and Pop together
        // ---------------------------------------------------------
        for (k = 0; k < 4; k = k + 1) begin
            drive(1, 1, 8'h0e - k);                    // push_data : 0e, 0d, 0c, 0b
            check(7, pop_data === (8'h0f - k));        // pop_data  : 0f, 0e, 0d, 0c
            w_b = wptr;
            r_b = rptr;
            wait_edge;
            check(7, wptr === ((w_b + 1) % 4) && rptr === ((r_b + 1) % 4));
            check(7, full === 1'b0 && empty === 1'b0);
        end

        // FIFO 비우기 (0b 1개가 남아 있음)
        drive(0, 1, 8'h00);
        wait_edge;
        check(7, empty === 1'b1);
        drive(0, 0, 8'h00);

        // ---------------------------------------------------------
        // Test Case 8 : push, pop, push_data = random (256 times) -> fail count = 0
        // ---------------------------------------------------------
        push_count = 0;
        pop_count = 0;
        for (i = 0; i < 256; i = i + 1) begin
            @(negedge clk);
            push = $random;
            pop = $random;
            push_data = $random;
            #1;
            // push 기대값 저장
            if (push && !full) begin
                compare_buffer[push_count] = push_data;
                push_count = push_count + 1;
            end
            // pop 기대값 비교
            if (pop && !empty) begin
                check(8, pop_data === compare_buffer[pop_count]);
                pop_count = pop_count + 1;
                rand_pop_count = rand_pop_count + 1;
            end
        end
        @(negedge clk);
        push = 0;
        pop = 0;

        // ---------------------------------------------------------
        // 결과 출력
        // ---------------------------------------------------------
        $display("*** FIFO TEST RESULT ***");
        for (i = 1; i <= 8; i = i + 1) begin
            if (tc_fail[i] == 0) $display("Test Case %0d : PASS", i);
            else $display("Test Case %0d : FAIL (%0d)", i, tc_fail[i]);
        end
        $display("random test : pop %0d times, fail %0d", rand_pop_count, tc_fail[8]);
        #100;
        $finish;
    end
endmodule