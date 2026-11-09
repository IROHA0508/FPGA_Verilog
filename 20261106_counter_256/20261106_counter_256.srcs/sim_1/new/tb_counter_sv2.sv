//v4 과제

`timescale 1ns / 1ps
interface counter_interface (
    input clk
);
    logic       rst;
    logic [7:0] counter;
    // ADD
    logic       mode;
    logic       run_stop;
    logic       clear;

    // ADD assertion
    property rst_zero;
        @(posedge clk) rst |=> (counter == 8'd0);
    endproperty

    assert_rst_zero :
    assert property (rst_zero)
    else begin
        $display("[Interface] rst = %d counter value error!1 %d", rst, counter);
    end
endinterface

class transaction;
    rand bit                rst;
    logic             [7:0] counter;
    // ADD
    rand bit                mode;
    rand bit                clear;

    // randc : 의미 찾기
    randc bit               run_stop;
    // run stop hold is for 3cyle over randomize
    rand int unsigned       run_stop_hold;


    function void debug_print(string name);
        $display(
            "%t : [%s] count = %d, rst = %d, mode = %d, run_stop  %d, clear = %d, hold = %d",
            $time, name, counter, rst, mode, run_stop, clear, run_stop_hold);
    endfunction

    // constraint mode, run_stop
    constraint mode_dist {
        mode dist {
            0 :/ 4,
            1 :/ 6
        };
    }

    constraint clear_dist {
        clear dist {
            0 :/ 9,
            1 :/ 1
        };
    }

    constraint run_stop_hold_range {
        run_stop_hold inside{
            [3:16]
        };
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

    task run(int count);
        repeat (count) begin
            tr = new;
            tr.randomize();
            gen2drv_mbox.put(tr);
            $display(
                "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++");
            tr.debug_print("GEN");
            @(gen_next_evt);
        end
    endtask

    // another control way
    bit enable = 1;
    task run_mode();
        while (enable) begin
            tr          = new;
            // tr.randomize();
            // mode = 0, 
            tr.rst      = 0;
            tr.mode     = 0;
            tr.run_stop = 1;
            tr.clear    = 0;
            gen2drv_mbox.put(tr);
            // ADD
            tr.debug_print("GEN");
            @(gen_next_evt);
        end
    endtask
endclass

class driver;
    transaction               tr;
    event                     gen_next_evt;
    mailbox #(transaction)    gen2drv_mbox;
    virtual counter_interface counter_interface_virtual;

    function new(mailbox#(transaction) gen2drv_mbox,
                 virtual counter_interface counter_interface_virtual,
                 event gen_next_evt);
        this.gen2drv_mbox              = gen2drv_mbox;
        this.counter_interface_virtual = counter_interface_virtual;
        this.gen_next_evt              = gen_next_evt;
    endfunction

    task reset();
        counter_interface_virtual.rst      = 1;
        counter_interface_virtual.mode     = 0;
        counter_interface_virtual.run_stop = 0;
        counter_interface_virtual.clear    = 0;
        @(negedge counter_interface_virtual.clk);
        @(negedge counter_interface_virtual.clk);
        counter_interface_virtual.rst = 0;
    endtask

    task run();
        forever begin
            @(negedge counter_interface_virtual.clk);
            gen2drv_mbox.get(tr);
            tr.debug_print("DRV");
            counter_interface_virtual.rst      = tr.rst;
            counter_interface_virtual.mode     = tr.mode;
            counter_interface_virtual.run_stop = tr.run_stop;
            counter_interface_virtual.clear    = tr.clear;

            // repeat (run_stop_hold - 1 )times
            repeat(tr.run_stop_hold - 1) begin             
                @(negedge counter_interface_virtual.clk);
                // counter_interface_virtual.rst      = tr.rst;
                // counter_interface_virtual.mode     = tr.mode;
                // counter_interface_virtual.run_stop = tr.run_stop;
                // counter_interface_virtual.clear    = tr.clear;
            end
            ->gen_next_evt;
        end
    endtask
endclass

class monitor;
    transaction tr;
    virtual counter_interface counter_interface_virtual;
    mailbox #(transaction) mon2scb_mbox;

    function new(mailbox#(transaction) mon2scb_mbox,
                 virtual counter_interface counter_interface_virtual);
        this.mon2scb_mbox              = mon2scb_mbox;
        this.counter_interface_virtual = counter_interface_virtual;
    endfunction


    task run();
        forever begin
            @(posedge counter_interface_virtual.clk);
            tr          = new;
            tr.rst      = counter_interface_virtual.rst;
            tr.counter  = counter_interface_virtual.counter;
            tr.mode     = counter_interface_virtual.mode;
            tr.run_stop = counter_interface_virtual.run_stop;
            tr.clear    = counter_interface_virtual.clear;
            mon2scb_mbox.put(tr);
            tr.debug_print("MON");
        end
    endtask
endclass

class scoreboad;
    transaction                  tr;
    logic                  [7:0] expected_count = 0;
    int                          pass_cnt       = 0;
    int                          fail_cnt       = 0;
    int                          total_cnt      = 0;
    mailbox #(transaction)       mon2scb_mbox;

    function new(mailbox#(transaction) mon2scb_mbox);
        this.mon2scb_mbox = mon2scb_mbox;
    endfunction

    task run();
        forever begin
            // [수정 1] monitor가 사이클당 1개 보내므로 get도 사이클당 딱 1번만
            //          (기존: get이 2번이라 샘플을 하나 건너뛰고 모델 갱신도 놓쳤음)
            mon2scb_mbox.get(tr);
            tr.debug_print("SCB");
            $display(
                "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++");

            if (tr.rst) begin
                // reset 구간: 비교는 건너뛰고 모델만 0으로 맞춤
                // (동기/비동기 reset 모두에서 안전)
                expected_count = 0;
            end else begin
                // [1단계] 비교: tr.counter는 이번 posedge "직전"의 DUT 값
                //         → 이번 입력을 반영하기 전의 모델값과 비교해야 함
                total_cnt++;
                if (expected_count === tr.counter) begin
                    pass_cnt++;
                end else begin
                    fail_cnt++;
                    $display("[SCB] FAIL : expected = %d, counter = %d",
                             expected_count, tr.counter);
                end

                // [2단계] 모델 갱신: 이번 posedge에서 DUT가 하게 될 동작을 반영
                if (tr.clear) expected_count = 0;  // clear > run_stop
                else if (tr.run_stop) begin
                    if (tr.mode) expected_count--;  // mode = 1 : down
                    else expected_count++;          // mode = 0 : up
                end  // run_stop = 0 이면 유지
            end
        end
    endtask

    task report();
        $display("***************REPORT******************");
        $display("*********************************");
        $display("Total : %d, Pass Count : %d, Fail Count : %d", total_cnt,
                 pass_cnt, fail_cnt);
        $display("END COUNT 256");
        $display("*********************************");
        $display("*********************************");
    endtask
endclass

class environment;
    transaction            tr;
    generator              gen;
    driver                 drv;
    monitor                mon;
    scoreboad              scb;
    event                  gen_next_evt;
    mailbox #(transaction) gen2drv_mbox;
    mailbox #(transaction) mon2scb_mbox;

    function new(virtual counter_interface counter_interface_virtual);
        gen2drv_mbox = new;
        mon2scb_mbox = new;

        gen = new(gen2drv_mbox, gen_next_evt);
        drv = new(gen2drv_mbox, counter_interface_virtual, gen_next_evt);
        mon = new(mon2scb_mbox, counter_interface_virtual);
        scb = new(mon2scb_mbox);
    endfunction

    task run(int run_count);
        drv.reset();
        fork
            gen.run(run_count);
            drv.run();
            mon.run();
            scb.run();
        join_any
        #1;
        scb.report();
        disable fork;
    endtask

    task run_mode();
        drv.reset();
        gen.enable = 1;
        fork
            gen.run_mode();
            drv.run();
            mon.run();
            scb.run();
        join_none
        #3000;
        gen.enable = 0;
        #10;
        scb.report();
        disable fork;
    endtask
endclass

module tb_counter_sv2 ();
    logic       clk = 0;
    environment env;

    counter_interface counter_interface (clk);

    counter_sv dut (
        .clk     (clk),
        .rst     (counter_interface.rst),
        .mode    (counter_interface.mode),
        .run_stop(counter_interface.run_stop),
        .clear   (counter_interface.clear),
        .counter (counter_interface.counter)
    );

    always #5 clk = ~clk;
    initial begin
        clk = 0;
        env = new(counter_interface);
        env.run(256);
        // env.run_mode();
        $finish;
    end
endmodule