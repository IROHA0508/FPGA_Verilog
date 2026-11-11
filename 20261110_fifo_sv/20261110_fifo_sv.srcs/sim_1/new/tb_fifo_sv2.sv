`timescale 1ns / 1ps
interface fifo_interface (
    input logic clk
);
    logic       rst;
    logic [7:0] push_data;
    logic       push;
    logic       pop;
    logic [7:0] pop_data;
    logic       full;
    logic       empty;

    // reset assertion
    property p_rst_full;
        // case compare, include x, z 
        @(posedge clk) rst |-> (full === 1'b0);
    endproperty

    property p_rst_empty;
        // case compare, include x, z 
        @(posedge clk) rst |-> (empty === 1'b1);
    endproperty

    
    a_rst_full : assert property (p_rst_full)
    else $display("%t : error full = %d", $time, full);

    a_rst_empty : assert property (p_rst_empty)
    else $display("%t : error empty = %d", $time, empty);

endinterface

class transaction;
    // input
    rand bit       rst;
    rand bit [7:0] push_data;
    rand bit       push;
    rand bit       pop;

    // output
    logic    [7:0] pop_data;
    logic          full;
    logic          empty;

    function void debug_print(string name);
        $display(
            "%t : [%s], rst = %d, push_data = %d, push = %d, pop = %d, pop_data = %d, full = %d, empty = %d",
            $time, name, rst, push_data, push, pop, pop_data, full, empty);
    endfunction

    constraint c_push {
        push dist {
            0 :/ 1,
            1 :/ 9
        };
    }

    constraint c_reset {
        rst dist {
            0 :/ 9,
            1 :/ 1
        };
    }

    constraint c_pop {
        pop dist {
            0 :/ 7,
            1 :/ 3
        };
    }
    int scenario;
    // automation by scenario num
    // 시나리오 값으로 확률 조작 가능 : 예시로 if 문으로 작성해 둔 것
    constraint test_scenario {
        if (scenario == 1) {
            // push only
            push dist {
                0 :/ 0,
                1 :/ 10
            };
            pop dist {
                0 :/ 10,
                1 :/ 0
            };
        } else
        if (scenario == 2) {
            // pop only
            pop dist {
                0 :/ 0,
                1 :/ 10
            };
            push dist {
                0 :/ 10,
                1 :/ 0
            };
        }
    }
endclass

class generator;
    transaction            tr;
    event                  gen_next_evt;
    mailbox #(transaction) gen2drv_mbox;

    function new(mailbox#(transaction) gen2drv_mbox, event gen_next_evt);
        this.gen2drv_mbox = gen2drv_mbox;
        this.gen_next_evt = gen_next_evt;
    endfunction

    task run(int run_count);
        repeat (run_count) begin
            tr = new;
            tr.randomize();
            // tr.rst      = 0;
            // tr.push     = 0;
            // tr.pop      = 1;
            // tr.scenario = 1;
            gen2drv_mbox.put(tr);
            $display("----------------------------------------------------");
            tr.debug_print("GEN");
            @(gen_next_evt);
        end
    endtask
endclass

class driver;
    transaction            tr;
    event                  mon_next_evt;
    mailbox #(transaction) gen2drv_mbox;
    virtual fifo_interface fifo_interface_virtual;

    function new(mailbox#(transaction) gen2drv_mbox, event mon_next_evt,
                 virtual fifo_interface fifo_interface_virtual);
        this.gen2drv_mbox = gen2drv_mbox;
        this.mon_next_evt = mon_next_evt;
        this.fifo_interface_virtual = fifo_interface_virtual;
    endfunction

    task reset();
        fifo_interface_virtual.rst       = 1;
        fifo_interface_virtual.push      = 0;
        fifo_interface_virtual.push_data = 0;
        fifo_interface_virtual.pop       = 0;
        @(negedge fifo_interface_virtual.clk);
        @(negedge fifo_interface_virtual.clk);
        fifo_interface_virtual.rst = 0;
    endtask

    task run();
        forever begin
            // posedge + 1ns
            @(posedge fifo_interface_virtual.clk);
            #1;

            gen2drv_mbox.get(tr);
            // input 4개
            fifo_interface_virtual.rst       = tr.rst;
            fifo_interface_virtual.push_data = tr.push_data;
            fifo_interface_virtual.push      = tr.push;
            fifo_interface_virtual.pop       = tr.pop;
            tr.debug_print("DRV");
            ->mon_next_evt;
        end
    endtask
endclass

class monitor;
    transaction            tr;
    mailbox #(transaction) mon2scb_mbox;
    event                  mon_next_evt;
    virtual fifo_interface fifo_interface_virtual;

    function new(mailbox#(transaction) mon2scb_mbox, event mon_next_evt,
                 virtual fifo_interface fifo_interface_virtual);
        this.mon2scb_mbox           = mon2scb_mbox;
        this.mon_next_evt           = mon_next_evt;
        this.fifo_interface_virtual = fifo_interface_virtual;
    endfunction

    task run();
        forever begin
            @(mon_next_evt);
            @(negedge fifo_interface_virtual.clk);
            tr           = new;
            tr.rst       = fifo_interface_virtual.rst;
            tr.push_data = fifo_interface_virtual.push_data;
            tr.push      = fifo_interface_virtual.push;
            tr.pop       = fifo_interface_virtual.pop;
            tr.pop_data  = fifo_interface_virtual.pop_data;
            tr.full      = fifo_interface_virtual.full;
            tr.empty     = fifo_interface_virtual.empty;

            mon2scb_mbox.put(tr);
            tr.debug_print("MON");
        end
    endtask
endclass

class scoreboard;
    transaction            tr;
    event                  gen_next_evt;
    mailbox #(transaction) mon2scb_mbox;

    // 기대값 모델 (FIFO depth = 4)
    localparam int DEPTH = 4;
    logic [7:0] expect_fifo_data[$:3];

    int total_cnt = 0;
    int pass_cnt = 0;
    int fail_cnt = 0;
    int full_cnt = 0;
    int empty_cnt = 0;

    function new(mailbox#(transaction) mon2scb_mbox, event gen_next_evt);
        this.mon2scb_mbox = mon2scb_mbox;
        this.gen_next_evt = gen_next_evt;
    endfunction

    function void check(transaction tr);
        bit exp_empty, exp_full;
        bit do_push, do_pop, ok;
        bit [7:0] exp_data;

        total_cnt++;
        ok = 1;

        // reset: 모델 초기화, 리셋 직후 값 확인
        if (tr.rst) begin
            expect_fifo_data.delete();
            if (tr.empty !== 1'b1 || tr.full !== 1'b0) begin
                ok = 0;
                $display("[SCB][FAIL] reset: empty=%0b full=%0b", tr.empty,
                         tr.full);
            end
            if (ok) pass_cnt++;
            else fail_cnt++;
            return;
        end

        // 1) 플래그 검사 (이번 트랜잭션 적용 "전" 모델 상태 기준)
        exp_empty = (expect_fifo_data.size() == 0);
        exp_full  = (expect_fifo_data.size() == DEPTH);

        if (exp_empty) empty_cnt++;
        if (exp_full) full_cnt++;

        if (tr.empty !== exp_empty) begin
            ok = 0;
            $display("[SCB][FAIL] empty: exp=%0b act=%0b", exp_empty, tr.empty);
        end
        if (tr.full !== exp_full) begin
            ok = 0;
            $display("[SCB][FAIL] full : exp=%0b act=%0b", exp_full, tr.full);
        end

        // DUT와 같은 규칙: full이면 push 무시, empty면 pop 무시
        do_pop  = tr.pop && !exp_empty;
        do_push = tr.push && !exp_full;

        // 2) pop_data 검사 + 3) 모델 갱신
        if (do_pop) begin
            exp_data = expect_fifo_data.pop_front();
            if (tr.pop_data !== exp_data) begin
                ok = 0;
                $display("[SCB][FAIL] pop_data: exp=%h act=%h", exp_data,
                         tr.pop_data);
            end
        end
        if (do_push) expect_fifo_data.push_back(tr.push_data);

        // 4) 카운트
        if (ok) pass_cnt++;
        else fail_cnt++;
    endfunction

    task run();
        forever begin
            mon2scb_mbox.get(tr);
            tr.debug_print("SCB");
            check(tr);
            $display("----------------------------------------------------");
            ->gen_next_evt;
        end
    endtask

    task report();
        $display("====================================================");
        $display("  SCOREBOARD REPORT");
        $display("  total_cnt = %0d", total_cnt);
        $display("  pass_cnt  = %0d", pass_cnt);
        $display("  fail_cnt  = %0d", fail_cnt);
        $display("  full_cnt  = %0d", full_cnt);
        $display("  empty_cnt = %0d", empty_cnt);
        if (full_cnt == 0)
            $display(
                "  WARNING   : full 상태가 한 번도 검증되지 않음"
            );
        if (empty_cnt == 0)
            $display(
                "  WARNING   : empty 상태가 한 번도 검증되지 않음"
            );
        if (fail_cnt == 0 && total_cnt > 0) $display("  RESULT    : PASS");
        else $display("  RESULT    : FAIL");
        $display("====================================================");
    endtask
endclass

class environment;
    generator              gen;
    driver                 drv;
    monitor                mon;
    scoreboard             scb;

    transaction            tr;
    event                  gen_next_evt;
    event                  mon_next_evt;

    mailbox #(transaction) gen2drv_mbox;
    mailbox #(transaction) mon2scb_mbox;

    function new(virtual fifo_interface fifo_interface_virtual);
        gen2drv_mbox = new;
        mon2scb_mbox = new;

        gen = new(gen2drv_mbox, gen_next_evt);
        drv = new(gen2drv_mbox, mon_next_evt, fifo_interface_virtual);
        mon = new(mon2scb_mbox, mon_next_evt, fifo_interface_virtual);
        scb = new(mon2scb_mbox, gen_next_evt);
    endfunction

    task run(int run_count);
        drv.reset();
        fork
            gen.run(run_count);
            drv.run();
            mon.run();
            scb.run();
        join_any
        #10;
        scb.report();
    endtask
endclass


module tb_fifo_sv2 ();
    logic clk = 0;

    fifo_interface fifo_interface (clk);
    environment env;

    fifo_sv dut (
        .clk      (clk),
        .rst      (fifo_interface.rst),
        .push_data(fifo_interface.push_data),
        .push     (fifo_interface.push),
        .pop      (fifo_interface.pop),
        .pop_data (fifo_interface.pop_data),
        .full     (fifo_interface.full),
        .empty    (fifo_interface.empty)
    );

    always #5 clk = ~clk;

    initial begin
        env = new(fifo_interface);
        env.run(300);
        $finish;
    end
endmodule
