`timescale 1ns / 1ps

typedef enum {OP_RESET, OP_CLEAR, OP_STOP, OP_UP, OP_DOWN} op_e;

interface counter_interface (
    input clk
);
    logic       rst;
    logic [7:0] counter;
    // ADD
    logic       mode;
    logic       run_stop;
    logic       clear;
endinterface

class transaction;
    rand bit       rst;
    logic    [7:0] counter;
    rand bit       mode;
    rand bit       run_stop;
    rand bit       clear;

    localparam int HOLD = 3;  // 최소 유지 clock 수

    // 이전 값
    bit prev_rst, prev_mode, prev_run_stop, prev_clear;
    // 연속 횟수
    int rst_cnt = 0, mode_cnt = 0, run_stop_cnt = 0, clear_cnt = 0;

    // 3번 미만이면 유지
    constraint c_rst_hold {if (rst_cnt > 0 && rst_cnt < HOLD) rst == prev_rst;}
    constraint c_mode_hold {
        if (mode_cnt > 0 && mode_cnt < HOLD) mode == prev_mode;
    }
    constraint c_run_stop_hold {
        if (run_stop_cnt > 0 && run_stop_cnt < HOLD) run_stop == prev_run_stop;
    }
    constraint c_clear_hold {
        if (clear_cnt > 0 && clear_cnt < HOLD) clear == prev_clear;
    }

    constraint c_mode {
        mode dist {
            0 :/ 4,
            1 :/ 6
        };
    }
    constraint c_run_stop {
        run_stop dist {
            0 :/ 3,
            1 :/ 7
        };
    }
    constraint c_rst {
        rst dist {
            0 :/ 95,
            1 :/ 5
        };
    }
    constraint c_clear {
        clear dist {
            0 :/ 9,
            1 :/ 1
        };
    }

    function void set_history(transaction p);
        prev_rst      = p.rst;
        rst_cnt       = p.rst_cnt;
        prev_mode     = p.mode;
        mode_cnt      = p.mode_cnt;
        prev_run_stop = p.run_stop;
        run_stop_cnt  = p.run_stop_cnt;
        prev_clear    = p.clear;
        clear_cnt     = p.clear_cnt;
    endfunction

    function void post_randomize();
        rst_cnt = (rst_cnt > 0 && rst == prev_rst) ? rst_cnt + 1 : 1;
        mode_cnt = (mode_cnt > 0 && mode == prev_mode) ? mode_cnt + 1 : 1;
        run_stop_cnt = (run_stop_cnt > 0 && run_stop == prev_run_stop) ? run_stop_cnt + 1 : 1;
        clear_cnt = (clear_cnt > 0 && clear == prev_clear) ? clear_cnt + 1 : 1;
    endfunction

    function void debug_print(string name);
        $display(
            "%t : [%s] count = %d, rst = %d, mode = %d, run_stop = %d, clear = %d",
            $time, name, counter, rst, mode, run_stop, clear);
    endfunction
endclass

class generator;
    transaction            tr;
    event                  gen_next_evt;
    mailbox #(transaction) gen2drv_mbox;

    // add
    transaction            prev_tr;

    function new(mailbox#(transaction) gen2drv_mbox, event gen_next_evt);
        this.gen2drv_mbox = gen2drv_mbox;
        this.gen_next_evt = gen_next_evt;
    endfunction

    task run(int count);
        repeat (count) begin
            tr = new;
            if (prev_tr != null) tr.set_history(prev_tr);
            tr.randomize();
            prev_tr = tr;
            gen2drv_mbox.put(tr);
            $display(
                "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++");
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
    op_e                         prev_op        = OP_RESET;
    op_e                         check_op;

    // total count
    int                          pass_cnt       = 0;
    int                          fail_cnt       = 0;
    int                          total_cnt      = 0;

    // 동작별 카운트
    int                          pass_op_cnt[5];
    int                          fail_op_cnt[5];
    int                          total_op_cnt[5];

    mailbox #(transaction)       mon2scb_mbox;

    function new(mailbox#(transaction) mon2scb_mbox);
        this.mon2scb_mbox = mon2scb_mbox;
    endfunction

    function op_e get_op(transaction t);
        if (t.rst)            return OP_RESET;
        else if (t.clear)     return OP_CLEAR;
        else if (!t.run_stop) return OP_STOP;
        else if (t.mode)      return OP_DOWN;
        else                  return OP_UP;
    endfunction

    task run();
        forever begin
            mon2scb_mbox.get(tr);

            // rst 인 경우
            if (tr.rst) begin
                expected_count = 0;      
                check_op       = OP_RESET;
            end else begin
                // rst 아니면 이전값 그대로 사용
                check_op = prev_op;     
            end

            total_cnt++;
            total_op_cnt[check_op]++;
            if (tr.counter == expected_count) begin
                pass_cnt++;
                pass_op_cnt[check_op]++;
            end else begin
                fail_cnt++;
                fail_op_cnt[check_op]++;
            end

            // operation 정보 확인
            prev_op = get_op(tr);
            if (!tr.rst) begin
                if (tr.clear) expected_count = 0;
                else if (tr.run_stop) begin
                    if (tr.mode) expected_count--;
                    else         expected_count++;
                end
                // run_stop = 0 이면 유지
            end
        end
    endtask

    task report();
        op_e op;
        $display("================ SCOREBOARD REPORT ================");
        for (int i = 0; i < 5; i++) begin
            op = op_e'(i);
            $display("%s : total = %3d, pass = %3d, fail = %3d",
                     op.name(), total_op_cnt[i], pass_op_cnt[i], fail_op_cnt[i]);
        end
        $display("---------------------------------------------------");
        $display("TOTAL    : total = %3d, pass = %3d, fail = %3d",
                 total_cnt, pass_cnt, fail_cnt);
        $display("===================================================");
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

module tb_counter_hw ();
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
