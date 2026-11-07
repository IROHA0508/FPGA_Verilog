`timescale 1ns / 1ps

// v1 기본 counter ===================================================
// interface counter_interface (
//     input clk
// );
//     logic       rst;
//     logic [7:0] counter;
// endinterface

// class transaction;
//     rand bit       rst;
//     logic    [7:0] counter;
// endclass

// class generator;
//     event gen_next_evt;

//     function new(event gen_next_evt);
//         this.gen_next_evt = gen_next_evt;
//     endfunction

//     task run(int count);
//         repeat (count) begin
//             // $display(
//             //     "=====================================================================");
//             @(gen_next_evt);
//         end
//     endtask
// endclass

// class driver;
//     event                     gen_next_evt;
//     virtual counter_interface counter_interface_virtual;

//     function new(virtual counter_interface counter_interface_virtual,
//                  event gen_next_evt);
//         this.counter_interface_virtual = counter_interface_virtual;
//         this.gen_next_evt              = gen_next_evt;
//     endfunction

//     task reset();
//         counter_interface_virtual.rst = 1;
//         @(negedge counter_interface_virtual.clk);
//         @(negedge counter_interface_virtual.clk);
//         counter_interface_virtual.rst = 0;
//     endtask

//     task run();
//         forever begin
//             @(posedge counter_interface_virtual.clk);
//             ->gen_next_evt;
//         end
//     endtask
// endclass

// class monitor;
//     transaction tr;
//     virtual counter_interface counter_interface_virtual;
//     mailbox #(transaction) mon2scb_mbox;

//     function new(mailbox#(transaction) mon2scb_mbox,
//                  virtual counter_interface counter_interface_virtual);
//         this.mon2scb_mbox              = mon2scb_mbox;
//         this.counter_interface_virtual = counter_interface_virtual;
//     endfunction


//     task run();
//         forever begin
//             @(posedge counter_interface_virtual.clk);
//             tr         = new;
//             tr.rst     = counter_interface_virtual.rst;
//             tr.counter = counter_interface_virtual.counter;
//             mon2scb_mbox.put(tr);
//         end
//     endtask
// endclass

// class scoreboad;
//     transaction                  tr;
//     logic                  [7:0] expected_count = 0;
//     int                          pass_cnt      = 0;
//     int                          fail_cnt      = 0;
//     int                          total_cnt     = 0;
//     mailbox #(transaction)       mon2scb_mbox;

//     function new(mailbox#(transaction) mon2scb_mbox);
//         this.mon2scb_mbox = mon2scb_mbox;
//     endfunction

//     task run();
//         forever begin
//             mon2scb_mbox.get(tr);
//             if (!tr.rst) begin
//                 total_cnt++;
//                 if (expected_count == tr.counter) begin
//                     pass_cnt++;
//                 end else begin
//                     fail_cnt++;
//                 end
//                 expected_count++;
//             end else begin
//                 expected_count = 0;
//             end
//             $display(
//                 "=====================================================================");
//         end
//     endtask

//     task report();
//         $display("*********************************");
//         $display("*********************************");
//         $display("Pass Count : %d, Fail Count : %d", pass_cnt, fail_cnt);
//         $display("END COUNT 256");
//         $display("*********************************");
//         $display("*********************************");
//     endtask
// endclass

// class environment;
//     transaction            tr;
//     generator              gen;
//     driver                 drv;
//     monitor                mon;
//     scoreboad              scb;
//     event                  gen_next_evt;
//     // mailbox #(transaction) gen2drv_mbox;
//     mailbox #(transaction) mon2scb_mbox;

//     function new(virtual counter_interface counter_interface_virtual);
//         // gen2drv_mbox = new;
//         mon2scb_mbox = new;

//         // gen = new(gen2drv_mbox, gen_next_evt);
//         // drv = new(gen2drv_mbox, counter_interface_virtual, gen_next_evt);
//         gen = new(gen_next_evt);
//         drv = new(counter_interface_virtual, gen_next_evt);
//         mon = new(mon2scb_mbox, counter_interface_virtual);
//         scb = new(mon2scb_mbox);
//     endfunction

//     task run(int run_count);
//         drv.reset();
//         fork
//             gen.run(run_count);
//             drv.run();
//             mon.run();
//             scb.run();
//         join_any
//         #10;
//         scb.report();
//         disable fork;
//     endtask
// endclass

// module tb_counter_sv ();
//     logic       clk = 0;
//     environment env;

//     counter_interface counter_interface (clk);

//     counter_sv dut (
//         .clk    (clk),
//         .rst    (counter_interface.rst),
//         .counter(counter_interface.counter)
//     );

//     always #5 clk = ~clk;
//     initial begin
//         clk = 0;
//         env = new(counter_interface);
//         env.run(256);
//         $finish;
//     end
// endmodule

// v2 mode, runstop, clear 추가 =========================================
// interface counter_interface (
//     input clk
// );
//     logic       rst;
//     logic [7:0] counter;
//     // ADD
//     logic       mode;
//     logic       run_stop;
//     logic       clear;
// endinterface

// class transaction;
//     rand bit       rst;
//     logic    [7:0] counter;
//     // ADD
//     rand bit       mode;
//     rand bit       run_stop;
//     rand bit       clear;

//     function void debug_print(string name);
//         $display("%t : [%s] count = %d, rst = %d, mode = %d, run_stop  %d, clear = %d",
//                  $time, name, counter, rst, mode, run_stop, clear);
//     endfunction

//     // constraint mode, run_stop
//     constraint c_mode {
//         mode dist {0 :/4, 1:/6};
//     }

//     constraint c_run_stop {
//         run_stop dist {0 :/3, 1 :/7};
//     }
// endclass

// class generator;
//     transaction            tr;
//     event                  gen_next_evt;
//     mailbox #(transaction) gen2drv_mbox;

//     function new(mailbox#(transaction) gen2drv_mbox, event gen_next_evt);
//         this.gen2drv_mbox = gen2drv_mbox;
//         this.gen_next_evt = gen_next_evt;
//     endfunction

//     task run(int count);
//         repeat (count) begin
//             tr = new;
//             tr.randomize();
//             gen2drv_mbox.put(tr);
//             $display("++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++");
//             @(gen_next_evt);
//         end
//     endtask

//     // another control way
//     bit enable = 1;
//     task run_mode();
//         while (enable) begin
//             tr          = new;
//             // tr.randomize();
//             // mode = 0, 
//             tr.rst      = 0;
//             tr.mode     = 0;
//             tr.run_stop = 1;
//             tr.clear    = 0;
//             gen2drv_mbox.put(tr);
//             // ADD
//             tr.debug_print("GEN");
//             @(gen_next_evt);
//         end
//     endtask
// endclass

// class driver;
//     transaction               tr;
//     event                     gen_next_evt;
//     mailbox #(transaction)    gen2drv_mbox;
//     virtual counter_interface counter_interface_virtual;

//     function new(mailbox#(transaction) gen2drv_mbox,
//                  virtual counter_interface counter_interface_virtual,
//                  event gen_next_evt);
//         this.gen2drv_mbox              = gen2drv_mbox;
//         this.counter_interface_virtual = counter_interface_virtual;
//         this.gen_next_evt              = gen_next_evt;
//     endfunction

//     task reset();
//         counter_interface_virtual.rst      = 1;
//         counter_interface_virtual.mode     = 0;
//         counter_interface_virtual.run_stop = 0;
//         counter_interface_virtual.clear    = 0;
//         @(negedge counter_interface_virtual.clk);
//         @(negedge counter_interface_virtual.clk);
//         counter_interface_virtual.rst = 0;
//     endtask

//     task run();
//         forever begin
//             @(negedge counter_interface_virtual.clk);
//             gen2drv_mbox.get(tr);
//             tr.debug_print("DRV");
//             counter_interface_virtual.rst      = tr.rst;
//             counter_interface_virtual.mode     = tr.mode;
//             counter_interface_virtual.run_stop = tr.run_stop;
//             counter_interface_virtual.clear    = tr.clear;
//             ->gen_next_evt;
//         end
//     endtask
// endclass

// class monitor;
//     transaction tr;
//     virtual counter_interface counter_interface_virtual;
//     mailbox #(transaction) mon2scb_mbox;

//     function new(mailbox#(transaction) mon2scb_mbox,
//                  virtual counter_interface counter_interface_virtual);
//         this.mon2scb_mbox              = mon2scb_mbox;
//         this.counter_interface_virtual = counter_interface_virtual;
//     endfunction


//     task run();
//         forever begin
//             @(posedge counter_interface_virtual.clk);
//             tr          = new;
//             tr.rst      = counter_interface_virtual.rst;
//             tr.counter  = counter_interface_virtual.counter;
//             tr.mode     = counter_interface_virtual.mode;
//             tr.run_stop = counter_interface_virtual.run_stop;
//             tr.clear    = counter_interface_virtual.clear;
//             mon2scb_mbox.put(tr);
//             tr.debug_print("MON");
//         end
//     endtask
// endclass

// class scoreboad;
//     transaction                  tr;
//     logic                  [7:0] expected_count = 0;
//     int                          pass_cnt       = 0;
//     int                          fail_cnt       = 0;
//     int                          total_cnt      = 0;
//     mailbox #(transaction)       mon2scb_mbox;

//     function new(mailbox#(transaction) mon2scb_mbox);
//         this.mon2scb_mbox = mon2scb_mbox;
//     endfunction

//     task run();
//         forever begin
//             mon2scb_mbox.get(tr);
//             tr.debug_print("SCB");
//             $display("++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++");
//             mon2scb_mbox.get(tr);
//             if (tr.rst) begin
//                 expected_count = 0;                 // counter가 이미 0이라 비교하면 의미 없음
//             end else begin
//                 total_cnt++;
//                 if (expected_count == tr.counter) pass_cnt++;
//                 else                              fail_cnt++;

//                 if (tr.clear)         expected_count = 0;        // clear > run_stop
//                 else if (tr.run_stop) begin
//                     if (tr.mode) expected_count--;
//                     else         expected_count++;
//                 end                                              // run_stop=0이면 유지
//             end
//         end
//     endtask

//     task report();
//         $display("***************REPORT******************");
//         $display("*********************************");
//         $display("Pass Count : %d, Fail Count : %d", pass_cnt, fail_cnt);
//         $display("END COUNT 256");
//         $display("*********************************");
//         $display("*********************************");
//     endtask
// endclass

// class environment;
//     transaction            tr;
//     generator              gen;
//     driver                 drv;
//     monitor                mon;
//     scoreboad              scb;
//     event                  gen_next_evt;
//     mailbox #(transaction) gen2drv_mbox;
//     mailbox #(transaction) mon2scb_mbox;

//     function new(virtual counter_interface counter_interface_virtual);
//         gen2drv_mbox = new;
//         mon2scb_mbox = new;

//         gen = new(gen2drv_mbox, gen_next_evt);
//         drv = new(gen2drv_mbox, counter_interface_virtual, gen_next_evt);
//         mon = new(mon2scb_mbox, counter_interface_virtual);
//         scb = new(mon2scb_mbox);
//     endfunction

//     task run(int run_count);
//         drv.reset();
//         fork
//             gen.run(run_count);
//             drv.run();
//             mon.run();
//             scb.run();
//         join_any
//         #1;
//         scb.report();
//         disable fork;
//     endtask

//     task run_mode ();
//         drv.reset();
//         gen.enable = 1;
//         fork
//             gen.run_mode();
//             drv.run();
//             mon.run();
//             scb.run();
//         join_none
//         #3000;
//         gen.enable = 0;
//         #10;
//         scb.report();
//         disable fork;
//     endtask
// endclass

// module tb_counter_sv ();
//     logic       clk = 0;
//     environment env;

//     counter_interface counter_interface (clk);

//     counter_sv dut (
//         .clk     (clk),
//         .rst     (counter_interface.rst),
//         .mode    (counter_interface.mode),
//         .run_stop(counter_interface.run_stop),
//         .clear   (counter_interface.clear),
//         .counter (counter_interface.counter)
//     );

//     always #5 clk = ~clk;
//     initial begin
//         clk = 0;
//         env = new(counter_interface);
//         env.run(256);
//         // env.run_mode();
//         $finish;
//     end
// endmodule


// v3 assertion 추가 ==================================
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

    assert_rst_zero : assert property(rst_zero)
    else begin 
        $display("[Interface] rst = %d counter value error!1 %d", rst, counter);
    end
endinterface

class transaction;
    rand bit       rst;
    logic    [7:0] counter;
    // ADD
    rand bit       mode;
    rand bit       run_stop;
    rand bit       clear;

    function void debug_print(string name);
        $display("%t : [%s] count = %d, rst = %d, mode = %d, run_stop  %d, clear = %d",
                 $time, name, counter, rst, mode, run_stop, clear);
    endfunction

    // constraint mode, run_stop
    constraint c_mode {
        mode dist {0 :/4, 1:/6};
    }

    constraint c_run_stop {
        run_stop dist {0 :/3, 1 :/7};
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
            $display("++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++");
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
    int                          pass_cnt       = 0;
    int                          fail_cnt       = 0;
    int                          total_cnt      = 0;
    mailbox #(transaction)       mon2scb_mbox;

    function new(mailbox#(transaction) mon2scb_mbox);
        this.mon2scb_mbox = mon2scb_mbox;
    endfunction

    task run();
        forever begin
            mon2scb_mbox.get(tr);
            tr.debug_print("SCB");
            $display("++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++");
            mon2scb_mbox.get(tr);
            if (tr.rst) begin
                expected_count = 0;                 // counter가 이미 0이라 비교하면 의미 없음
            end else begin
                total_cnt++;
                if (expected_count == tr.counter) pass_cnt++;
                else                              fail_cnt++;

                if (tr.clear)         expected_count = 0;        // clear > run_stop
                else if (tr.run_stop) begin
                    if (tr.mode) expected_count--;
                    else         expected_count++;
                end                                              // run_stop=0이면 유지
            end
        end
    endtask

    task report();
        $display("***************REPORT******************");
        $display("*********************************");
        $display("Pass Count : %d, Fail Count : %d", pass_cnt, fail_cnt);
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

    task run_mode ();
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

module tb_counter_sv ();
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
