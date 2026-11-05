`timescale 1ns / 1ps

// v5 ========================================================================================================================
// driver, monitor 순서 제어
// interface adder_interface ();
//     logic [7:0] a;
//     logic [7:0] b;
//     logic       mode;  // 0 : add, 1 : sub
//     logic [7:0] s;
//     logic       c;
// endinterface

// class transaction;
//     // drive variable
//     rand bit [7:0] a;
//     rand bit [7:0] b;
//     rand bit       mode;

//     // output variable
//     logic    [7:0] s;
//     logic          c;

//     // 추가
//     function debug_print(string name);
//         $display("%t : [%s] a = %d, b = %d, mode = %d, s = %d, c = %d", $time,
//                  name, a, b, mode, s, c);
//     endfunction
// endclass

// class generator;
//     transaction            tr;
//     mailbox #(transaction) gen2drv_mbox;

//     function new(mailbox#(transaction) gen2drv_mbox_args);
//         gen2drv_mbox = gen2drv_mbox_args;
//     endfunction

//     task run();
//         begin
//             tr = new;
//             // to generate for randomize stimulus by tr
//             tr.randomize();
//             $display(
//                 "========================================================================================================================");
//             tr.debug_print("GEN");
//             gen2drv_mbox.put(tr);
//         end
//     endtask
// endclass

// class driver;
//     transaction             tr;
//     virtual adder_interface adder_if_virtual;
//     mailbox #(transaction)  gen2drv_mbox;
//     // ADD event
//     event                   drv2mon_evt;

//     function new(mailbox#(transaction) gen2drv_mbox_args,
//                  event drv2mon_evt_args,
//                  virtual adder_interface adder_if_virtual_args);
//         gen2drv_mbox     = gen2drv_mbox_args;
//         drv2mon_evt      = drv2mon_evt_args;
//         adder_if_virtual = adder_if_virtual_args;
//     endfunction

//     task run();
//         begin
//             gen2drv_mbox.get(tr);
//             tr.debug_print("DRV");
//             // drive
//             adder_if_virtual.a    = tr.a;
//             adder_if_virtual.b    = tr.b;
//             adder_if_virtual.mode = tr.mode;
//             #10;

//             // send event
//             //  -> : make event, @ : catch event
//             // ->drv2mon_evt;
//         end
//     endtask
// endclass

// class monitor;
//     transaction             tr;
//     virtual adder_interface adder_if_virtual;
//     mailbox #(transaction)  mon2scb_mbox;

//     // event 변수 생성
//     event                   drv2mon_evt;

//     // args 붙이기 싫으면 this. 사용해도됨
//     // this : class 내부에서 선언한 변수를 가리킴
//     function new(mailbox#(transaction) mon2scb_mbox_args,
//                  event drv2mon_evt_args,
//                  virtual adder_interface adder_if_virtual_args);
//         mon2scb_mbox     = mon2scb_mbox_args;
//         drv2mon_evt      = drv2mon_evt_args;
//         adder_if_virtual = adder_if_virtual_args;
//         // this.mon2scb_mbox     = mon2scb_mbox_args;
//         // this.adder_if_virtual = adder_if_virtual_args;
//     endfunction

//     task run();
//         begin
//             // wait event
//             // wait 문 사용 or @로 이벤트 감지 : 둘다 써도 상관 없음
//             // wait(drv2mon_evt);
//             // @(drv2mon_evt);

//             // generate transaction
//             tr      = new;
//             tr.a    = adder_if_virtual.a;
//             tr.b    = adder_if_virtual.b;
//             tr.mode = adder_if_virtual.mode;
//             tr.s    = adder_if_virtual.s;
//             tr.c    = adder_if_virtual.c;
//             tr.debug_print("MON");

//             // put value in mailbox
//             mon2scb_mbox.put(tr);
//         end
//     endtask
// endclass

// class scoreboard;
//     transaction                  tr;
//     mailbox #(transaction)       mon2scb_mbox;
//     bit                    [7:0] expected_sum;
//     bit                          expected_carry;
//     int                          pass_cnt        = 0;
//     int                          fail_cnt        = 0;

//     function new(mailbox#(transaction) mon2scb_mbox_args);
//         mon2scb_mbox = mon2scb_mbox_args;
//     endfunction

//     task run();
//         // get transaction from mailbox
//         mon2scb_mbox.get(tr);
//         {expected_carry, expected_sum} = (tr.mode) ? tr.a - tr.b : tr.a + tr.b;
//         // pass, fail
//         if (expected_sum == tr.s && expected_carry == tr.c) begin
//             $display("PASS");
//             pass_cnt++;
//         end else begin
//             $display("FAIL");
//             $display(
//                 "Expected sum = %d, Expected carry = %d, Sum = %d, Carry = %d",
//                 expected_sum, expected_carry, tr.s, tr.c);
//             fail_cnt++;
//         end
//         tr.debug_print("SCB");
//     endtask
// endclass

// class environment;
//     generator              gen;
//     driver                 drv;
//     monitor                mon;
//     scoreboard             scb;
//     mailbox #(transaction) gen2drv_mbox;
//     mailbox #(transaction) mon2scb_mbox;
//     event                  drv2mon_evt;

//     function new(virtual adder_interface adder_interface_args);
//         gen2drv_mbox = new;
//         mon2scb_mbox = new;
//         gen = new(gen2drv_mbox);
//         drv = new(gen2drv_mbox, drv2mon_evt, adder_interface_args);
//         mon = new(mon2scb_mbox, drv2mon_evt, adder_interface_args);
//         scb = new(mon2scb_mbox);
//     endfunction

//     task run();
//         // control all classes in env
//         repeat (10) begin
//             gen.run();
//             drv.run();
//             mon.run();
//             scb.run();
//         end

//         $display("PASS : %d, FAIL : %d", scb.pass_cnt, scb.fail_cnt);
//     endtask
// endclass

// module tb_adder2 ();
//     environment env;
//     adder_interface adder_if ();

//     adder dut (
//         .a   (adder_if.a),
//         .b   (adder_if.b),
//         .mode(adder_if.mode),  // 0 : add, 1 : sub
//         .s   (adder_if.s),
//         .c   (adder_if.c)
//     );

//     initial begin
//         env = new(adder_if);
//         env.run();
//         $finish;
//     end
// endmodule

// v6 ========================================================================================================================
// ADD constraints
// interface adder_interface ();
//     logic [7:0] a;
//     logic [7:0] b;
//     logic       mode;  // 0 : add, 1 : sub
//     logic [7:0] s;
//     logic       c;
// endinterface

// class transaction;
//     // drive variable
//     rand bit [7:0] a;
//     rand bit [7:0] b;
//     rand bit       mode;

//     // output variable
//     logic    [7:0] s;
//     logic          c;

//     // ADD
//     function debug_print(string name);
//         $display("%t : [%s] a = %d, b = %d, mode = %d, s = %d, c = %d", $time,
//                  name, a, b, mode, s, c);
//     endfunction

//     // ADD range constraints
//     constraint adder_limit {
//         a > 128;
//         b < 64;
//     }

//     // constraint adder_instde{a inside {128, 200, 212, 250};}

//     constraint adder_dist {
//         mode dist{
//           0 :/80,
//           1 :/20  
//         };
//     };
// endclass

// class generator;
//     transaction            tr;
//     mailbox #(transaction) gen2drv_mbox;

//     function new(mailbox#(transaction) gen2drv_mbox_args);
//         gen2drv_mbox = gen2drv_mbox_args;
//     endfunction

//     task run();
//         begin
//             tr = new;
//             // to generate for randomize stimulus by tr
//             tr.randomize();
//             $display(
//                 "========================================================================================================================");
//             tr.debug_print("GEN");
//             gen2drv_mbox.put(tr);
//         end
//     endtask
// endclass

// class driver;
//     transaction             tr;
//     virtual adder_interface adder_if_virtual;
//     mailbox #(transaction)  gen2drv_mbox;
//     // ADD event
//     event                   drv2mon_evt;

//     function new(mailbox#(transaction) gen2drv_mbox_args,
//                  event drv2mon_evt_args,
//                  virtual adder_interface adder_if_virtual_args);
//         gen2drv_mbox     = gen2drv_mbox_args;
//         drv2mon_evt      = drv2mon_evt_args;
//         adder_if_virtual = adder_if_virtual_args;
//     endfunction

//     task run();
//         begin
//             gen2drv_mbox.get(tr);
//             tr.debug_print("DRV");
//             // drive
//             adder_if_virtual.a    = tr.a;
//             adder_if_virtual.b    = tr.b;
//             adder_if_virtual.mode = tr.mode;
//             #10;

//             // send event
//             //  -> : make event, @ : catch event
//             // ->drv2mon_evt;
//         end
//     endtask
// endclass

// class monitor;
//     transaction             tr;
//     virtual adder_interface adder_if_virtual;
//     mailbox #(transaction)  mon2scb_mbox;

//     // event 변수 생성
//     event                   drv2mon_evt;

//     // args 붙이기 싫으면 this. 사용해도됨
//     // this : class 내부에서 선언한 변수를 가리킴
//     function new(mailbox#(transaction) mon2scb_mbox_args,
//                  event drv2mon_evt_args,
//                  virtual adder_interface adder_if_virtual_args);
//         mon2scb_mbox     = mon2scb_mbox_args;
//         drv2mon_evt      = drv2mon_evt_args;
//         adder_if_virtual = adder_if_virtual_args;
//         // this.mon2scb_mbox     = mon2scb_mbox_args;
//         // this.adder_if_virtual = adder_if_virtual_args;
//     endfunction

//     task run();
//         begin
//             // wait event
//             // wait 문 사용 or @로 이벤트 감지 : 둘다 써도 상관 없음
//             // wait(drv2mon_evt);
//             // @(drv2mon_evt);

//             // generate transaction
//             tr      = new;
//             tr.a    = adder_if_virtual.a;
//             tr.b    = adder_if_virtual.b;
//             tr.mode = adder_if_virtual.mode;
//             tr.s    = adder_if_virtual.s;
//             tr.c    = adder_if_virtual.c;
//             tr.debug_print("MON");

//             // put value in mailbox
//             mon2scb_mbox.put(tr);
//         end
//     endtask
// endclass

// class scoreboard;
//     transaction                  tr;
//     mailbox #(transaction)       mon2scb_mbox;
//     bit                    [7:0] expected_sum;
//     bit                          expected_carry;
//     int                          pass_cnt        = 0;
//     int                          fail_cnt        = 0;

//     function new(mailbox#(transaction) mon2scb_mbox_args);
//         mon2scb_mbox = mon2scb_mbox_args;
//     endfunction

//     task run();
//         // get transaction from mailbox
//         mon2scb_mbox.get(tr);
//         {expected_carry, expected_sum} = (tr.mode) ? tr.a - tr.b : tr.a + tr.b;
//         // pass, fail
//         if (expected_sum == tr.s && expected_carry == tr.c) begin
//             $display("PASS");
//             pass_cnt++;
//         end else begin
//             $display("FAIL");
//             $display(
//                 "Expected sum = %d, Expected carry = %d, Sum = %d, Carry = %d",
//                 expected_sum, expected_carry, tr.s, tr.c);
//             fail_cnt++;
//         end
//         tr.debug_print("SCB");
//     endtask
// endclass

// class environment;
//     generator              gen;
//     driver                 drv;
//     monitor                mon;
//     scoreboard             scb;
//     mailbox #(transaction) gen2drv_mbox;
//     mailbox #(transaction) mon2scb_mbox;
//     event                  drv2mon_evt;

//     function new(virtual adder_interface adder_interface_args);
//         gen2drv_mbox = new;
//         mon2scb_mbox = new;
//         gen = new(gen2drv_mbox);
//         drv = new(gen2drv_mbox, drv2mon_evt, adder_interface_args);
//         mon = new(mon2scb_mbox, drv2mon_evt, adder_interface_args);
//         scb = new(mon2scb_mbox);
//     endfunction

//     // ADD arguments
//     task run(int run_count);
//         // control all classes in env
//         repeat (run_count) begin
//             gen.run();
//             drv.run();
//             mon.run();
//             scb.run();
//         end

//         $display("PASS : %d, FAIL : %d", scb.pass_cnt, scb.fail_cnt);
//     endtask
// endclass

// module tb_adder2 ();
//     environment env;
//     adder_interface adder_if ();

//     adder dut (
//         .a   (adder_if.a),
//         .b   (adder_if.b),
//         .mode(adder_if.mode),  // 0 : add, 1 : sub
//         .s   (adder_if.s),
//         .c   (adder_if.c)
//     );

//     initial begin
//         env = new(adder_if);
//         env.run(20);
//         $finish;
//     end
// endmodule

// v7 ========================================================================================================================
// fork - join

interface adder_interface ();
    logic [7:0] a;
    logic [7:0] b;
    logic       mode;  // 0 : add, 1 : sub
    logic [7:0] s;
    logic       c;
endinterface

class transaction;
    // drive variable
    rand bit [7:0] a;
    rand bit [7:0] b;
    rand bit       mode;

    // output variable
    logic    [7:0] s;
    logic          c;

    // ADD
    function debug_print(string name);
        $display("%t : [%s] a = %d, b = %d, mode = %d, s = %d, c = %d", $time,
                 name, a, b, mode, s, c);
    endfunction

    // ADD range constraints
    constraint adder_limit {
        a > 128;
        b < 64;
    }

    // constraint adder_instde{a inside {128, 200, 212, 250};}

    constraint adder_dist {
        mode dist {
            0 :/ 80,
            1 :/ 20
        };
    }
    ;
endclass

class generator;
    transaction            tr;
    mailbox #(transaction) gen2drv_mbox;
    event                  gen_next_evt;
    function new(mailbox#(transaction) gen2drv_mbox_args,
                 event gen_next_evt_args);
        gen2drv_mbox = gen2drv_mbox_args;
        gen_next_evt = gen_next_evt_args;
    endfunction

    task run(int run_count);
        repeat (run_count) begin
            tr = new;
            // to generate for randomize stimulus by tr
            tr.randomize();
            $display(
                "========================================================================================================================");
            tr.debug_print("GEN");
            gen2drv_mbox.put(tr);

            // wait gen next event
            @(gen_next_evt);
        end
        $display("%t : END GEN", $time);
    endtask
endclass

class driver;
    transaction             tr;
    virtual adder_interface adder_if_virtual;
    mailbox #(transaction)  gen2drv_mbox;
    // ADD event
    event                   drv2mon_evt;

    function new(mailbox#(transaction) gen2drv_mbox_args,
                 event drv2mon_evt_args,
                 virtual adder_interface adder_if_virtual_args);
        gen2drv_mbox     = gen2drv_mbox_args;
        drv2mon_evt      = drv2mon_evt_args;
        adder_if_virtual = adder_if_virtual_args;
    endfunction

    task run();
        forever begin
            gen2drv_mbox.get(tr);
            tr.debug_print("DRV");
            // drive
            adder_if_virtual.a    = tr.a;
            adder_if_virtual.b    = tr.b;
            adder_if_virtual.mode = tr.mode;
            #5;

            // send event
            //  -> : make event, @ : catch event
            ->drv2mon_evt;
            #5;
        end
    endtask
endclass

class monitor;
    transaction             tr;
    virtual adder_interface adder_if_virtual;
    mailbox #(transaction)  mon2scb_mbox;

    // event 변수 생성
    event                   drv2mon_evt;

    // args 붙이기 싫으면 this. 사용해도됨
    // this : class 내부에서 선언한 변수를 가리킴
    function new(mailbox#(transaction) mon2scb_mbox_args,
                 event drv2mon_evt_args,
                 virtual adder_interface adder_if_virtual_args);
        mon2scb_mbox     = mon2scb_mbox_args;
        drv2mon_evt      = drv2mon_evt_args;
        adder_if_virtual = adder_if_virtual_args;
        // this.mon2scb_mbox     = mon2scb_mbox_args;
        // this.adder_if_virtual = adder_if_virtual_args;
    endfunction

    task run();
        forever begin
            // wait event
            // wait 문 사용 or @로 이벤트 감지 : 둘다 써도 상관 없음
            // wait(drv2mon_evt);
            @(drv2mon_evt);

            // generate transaction
            tr      = new;
            tr.a    = adder_if_virtual.a;
            tr.b    = adder_if_virtual.b;
            tr.mode = adder_if_virtual.mode;
            tr.s    = adder_if_virtual.s;
            tr.c    = adder_if_virtual.c;
            tr.debug_print("MON");

            // put value in mailbox
            mon2scb_mbox.put(tr);
        end
    endtask
endclass

class scoreboard;
    transaction                  tr;
    mailbox #(transaction)       mon2scb_mbox;
    event                        gen_next_evt;

    bit                    [7:0] expected_sum;
    bit                          expected_carry;
    int                          pass_cnt        = 0;
    int                          fail_cnt        = 0;

    function new(mailbox#(transaction) mon2scb_mbox_args,
                 event gen_next_evt_args);
        mon2scb_mbox = mon2scb_mbox_args;
        gen_next_evt = gen_next_evt_args;
    endfunction

    task run();
        forever begin
            // get transaction from mailbox
            mon2scb_mbox.get(tr);
            {expected_carry, expected_sum} = (tr.mode) ? tr.a - tr.b : tr.a + tr.b;
            // pass, fail
            if (expected_sum == tr.s && expected_carry == tr.c) begin
                $display("PASS");
                pass_cnt++;
            end else begin
                $display("FAIL");
                $display(
                    "Expected sum = %d, Expected carry = %d, Sum = %d, Carry = %d",
                    expected_sum, expected_carry, tr.s, tr.c);
                fail_cnt++;
            end
            tr.debug_print("SCB");

            // send gen_next_evt
            -> gen_next_evt;
        end
    endtask
endclass

class environment;
    generator              gen;
    driver                 drv;
    monitor                mon;
    scoreboard             scb;

    mailbox #(transaction) gen2drv_mbox;
    mailbox #(transaction) mon2scb_mbox;

    event                  drv2mon_evt;
    event                  gen_next_evt;

    function new(virtual adder_interface adder_interface_args);
        gen2drv_mbox = new;
        mon2scb_mbox = new;
        gen          = new(gen2drv_mbox, gen_next_evt);
        drv          = new(gen2drv_mbox, drv2mon_evt, adder_interface_args);
        mon          = new(mon2scb_mbox, drv2mon_evt, adder_interface_args);
        scb          = new(mon2scb_mbox, gen_next_evt);
    endfunction

    // ADD arguments
    task run(int run_count);
        // control all classes in env
        fork
            gen.run(run_count);
            drv.run();
            mon.run();
            scb.run();
        join_any
        #100;
        $display("%t : end fork join", $time);
        $display("PASS : %d, FAIL : %d", scb.pass_cnt, scb.fail_cnt);
    endtask
endclass

module tb_adder2 ();
    environment env;
    adder_interface adder_if ();

    adder dut (
        .a   (adder_if.a),
        .b   (adder_if.b),
        .mode(adder_if.mode),  // 0 : add, 1 : sub
        .s   (adder_if.s),
        .c   (adder_if.c)
    );

    initial begin
        env = new(adder_if);
        env.run(20);
        $finish;
    end
endmodule
