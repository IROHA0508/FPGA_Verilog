`timescale 1ns / 1ps

// v1 ========================================================================================================================
// interface adder_interface (
//     input  logic [7:0] a,
//     input  logic [7:0] b,
//     input  logic       mode,  // 0 : add, 1 : sub
//     output logic [7:0] s,
//     output logic       c
// );
// endinterface

// module tb_adder ();
//     // reg, wire 대신 logic이라 해도 됨
//     // reg [7:0] a, b;
//     // reg        mode;
//     // wire [7:0] s;
//     // wire       c;
//     logic [7:0] a, b;
//     logic       mode;
//     logic [7:0] s;
//     logic       c;

//     adder_interface adder_if (
//         .a   (a),
//         .b   (b),
//         .mode(mode),  // 0 : add, 1 : sub
//         .s   (s),
//         .c   (c)
//     );

//     adder dut (
//         // 1. 기존 방식
//         // .a   (a),
//         // .b   (b),
//         // .mode(mode),  // 0 : add, 1 : sub
//         // .s   (s),
//         // .c   (c)

//         // 2. 한번에 매칭
//         // .*

//         // 3. interface를 이용한 매칭
//         .a   (adder_if.a),
//         .b   (adder_if.b),
//         .mode(adder_if.mode),  // 0 : add, 1 : sub
//         .s   (adder_if.s),
//         .c   (adder_if.c)
//     );

//     initial begin
//         for (int i = 0; i < 256; i++) begin
//             a = i;
//             b = 256 - i;
//             mode = 0;
//             #10;
//         end
//         gen = new()
//         $finish;
//     end
// endmodule

// v2 ========================================================================================================================
// class transaction;
//     // drive variable
//     rand bit   [7:0] a;
//     rand bit   [7:0] b;
//     rand bit         mode;

//     // output variable
//     logic [7:0] s;
//     logic       c;
// endclass

// class generator;
//     transaction tr;
//     virtual adder_interface adder_if_virtual;

//     function new(virtual adder_interface adder_if_virtual_args); 
//         adder_if_virtual = adder_if_virtual_args;
//         tr = new;
//     endfunction

//     task run();
//         repeat(10) begin 
//             // to generate for randomize stimulus by tr
//             tr.randomize();
//             // drive
//             adder_if_virtual.a = tr.a;
//             adder_if_virtual.b = tr.b;
//             adder_if_virtual.mode = tr.mode;
//             #10;
//         end
//     endtask
// endclass

// interface adder_interface();
//     logic [7:0] a;
//     logic [7:0] b;
//     logic       mode;  // 0 : add, 1 : sub
//     logic [7:0] s;
//     logic       c;
// endinterface

// module tb_adder ();
//     logic [7:0] a, b;
//     logic       mode;
//     logic [7:0] s;
//     logic       c;

//     adder_interface adder_if ();

//     generator gen;

//     adder dut (
//         .a   (adder_if.a),
//         .b   (adder_if.b),
//         .mode(adder_if.mode),  // 0 : add, 1 : sub
//         .s   (adder_if.s),
//         .c   (adder_if.c)
//     );

//     initial begin
//         gen = new(adder_if);
//         gen.run();
//         $finish;
//     end
// endmodule

// v3 ========================================================================================================================
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
// endclass

// class generator;
//     transaction tr;
//     mailbox #(transaction) gen2drv_mbox;

//     function new(mailbox#(transaction) gen2drv_mbox_args);
//         gen2drv_mbox = gen2drv_mbox_args;
//     endfunction

//     task run();
//         repeat (10) begin
//             tr = new;
//             // to generate for randomize stimulus by tr
//             tr.randomize();
//             gen2drv_mbox.put(tr);
//         end
//     endtask
// endclass

// class driver;
//     transaction tr;
//     virtual adder_interface adder_if_virtual;
//     mailbox #(transaction) gen2drv_mbox;

//     function new(mailbox#(transaction) gen2drv_mbox_args,
//                  virtual adder_interface adder_if_virtual_args);
//         gen2drv_mbox     = gen2drv_mbox_args;
//         adder_if_virtual = adder_if_virtual_args;
//     endfunction

//     task run();
//         forever begin
//             gen2drv_mbox.get(tr);
//             // drive
//             adder_if_virtual.a    = tr.a;
//             adder_if_virtual.b    = tr.b;
//             adder_if_virtual.mode = tr.mode;
//             #10;
//         end
//     endtask
// endclass

// class environment;
//     generator              gen;
//     driver                 drv;
//     mailbox #(transaction) gen2drv_mbox;

//     function new(virtual adder_interface adder_interface_args);
//         gen2drv_mbox = new;
//         gen = new(gen2drv_mbox);
//         drv = new(gen2drv_mbox, adder_interface_args);
//     endfunction

//     task run(); 
//         forever begin 
//             gen.run();
//             drv.run();
//         end
//     endtask
// endclass

// module tb_adder ();
//     logic [7:0] a, b;
//     logic       mode;
//     logic [7:0] s;
//     logic       c;

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



// v4 ========================================================================================================================
// transaction에 Debug Print 추가
interface adder_interface ();
    logic [7:0] a;
    logic [7:0] b;
    logic       mode;  // 0 : add, 1 : sub
    logic [8:0] s;
    logic       c;
endinterface

class transaction;
    // drive variable
    rand bit [7:0] a;
    rand bit [7:0] b;
    rand bit       mode;

    // output variable
    logic    [8:0] s;
    logic          c;

    // 추가
    function debug_print(string name);
        $display("%t : [%s] a = %d, b = %d, mode = %d, s = %d, c = %d", $time, name, a, b, mode, s, c);
    endfunction
endclass

class generator;
    transaction tr;
    mailbox #(transaction) gen2drv_mbox;

    function new(mailbox#(transaction) gen2drv_mbox_args);
        gen2drv_mbox = gen2drv_mbox_args;
    endfunction

    task run();
        repeat (256) begin
            tr = new;
            // to generate for randomize stimulus by tr
            tr.randomize();
            tr.debug_print("GEN");
            gen2drv_mbox.put(tr);
        end
    endtask
endclass

class driver;
    transaction tr;
    virtual adder_interface adder_if_virtual;
    mailbox #(transaction) gen2drv_mbox;

    function new(mailbox#(transaction) gen2drv_mbox_args,
                 virtual adder_interface adder_if_virtual_args);
        gen2drv_mbox     = gen2drv_mbox_args;
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
            #10;
        end
    endtask
endclass

class environment;
    generator              gen;
    driver                 drv;
    mailbox #(transaction) gen2drv_mbox;

    function new(virtual adder_interface adder_interface_args);
        gen2drv_mbox = new;
        gen = new(gen2drv_mbox);
        drv = new(gen2drv_mbox, adder_interface_args);
    endfunction

    task run(); 
        forever begin 
            gen.run();
            drv.run();
        end
    endtask
endclass

module tb_adder ();
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
        env.run();
        $finish;
    end
endmodule