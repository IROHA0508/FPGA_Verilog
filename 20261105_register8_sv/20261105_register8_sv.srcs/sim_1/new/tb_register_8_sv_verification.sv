`timescale 1ns / 1ps

interface reg_interface (
    input clk
);
    logic       rst;
    logic [7:0] d;
    logic [7:0] q;
endinterface

class transaction;
    // drive input
    bit            rst;
    rand bit [7:0] d;
    // result output
    logic    [7:0] q;

    function debug_print(string name);
        $display("%t ns : [%s] reset = %d, d = %d, q = %d", $time, name, rst,
                 d, q);
    endfunction
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
            $display("=======================================================================================");
            tr = new;
            tr.randomize();
            tr.debug_print("GEN - random");
            // to driver
            gen2drv_mbox.put(tr);
            tr.debug_print("GEN - put");
            // from scoreboad
            @(gen_next_evt);
        end
    endtask
endclass

class driver;
    transaction            tr;
    virtual reg_interface  reg_interface_virtual;
    event                  mon_next_evt;
    mailbox #(transaction) gen2drv_mbox;

    function new(mailbox#(transaction) gen2drv_mbox,
                 virtual reg_interface reg_interface_virtual,
                 event mon_next_evt);
        this.gen2drv_mbox          = gen2drv_mbox;
        this.reg_interface_virtual = reg_interface_virtual;
        this.mon_next_evt          = mon_next_evt;
    endfunction

    // Flip flop needs reset once
    task reset();
        begin
            reg_interface_virtual.rst = 1;
            @(posedge reg_interface_virtual.clk);
            @(posedge reg_interface_virtual.clk);
        end
    endtask


    task run();
        forever begin
            // sense posedge clk using virtual interface
            // (1) cost 2 cycles
            gen2drv_mbox.get(tr);
            tr.debug_print("DRV - get");
            @(posedge reg_interface_virtual.clk);

            // (2) cost 1 cycle
            // @(posedge reg_interface_virtual.clk);
            // gen2drv_mbox.get(tr);
            // tr.debug_print("DRV - get");

            // using neg edge -> cost 1cycle            
            // @(negedge reg_interface_virtual.clk);
            // gen2drv_mbox.get(tr);
            // tr.debug_print("DRV - get");
            #1;
            tr.debug_print("DRV - after posedge");
            reg_interface_virtual.rst = 0;
            reg_interface_virtual.d   = tr.d;
            // send event
            ->mon_next_evt;
        end
    endtask
endclass

class monitor;
    transaction            tr;
    virtual reg_interface  reg_interface_virtual;
    event                  mon_next_evt;
    mailbox #(transaction) mon2scb_mbox;

    function new(mailbox#(transaction) mon2scb_mbox,
                 virtual reg_interface reg_interface_virtual,
                 event mon_next_evt);
        this.mon_next_evt          = mon_next_evt;
        this.reg_interface_virtual = reg_interface_virtual;
        this.mon2scb_mbox          = mon2scb_mbox;
    endfunction

    task run();
        forever begin
            tr = new;
            @(mon_next_evt);
            tr.debug_print("MON - get event");
            @(posedge reg_interface_virtual.clk);
            tr.rst = reg_interface_virtual.rst;
            tr.d   = reg_interface_virtual.d;
            tr.q   = reg_interface_virtual.q;
            tr.debug_print("MON - after posedge");
            mon2scb_mbox.put(tr);
        end
    endtask
endclass

class scoreboard;
    transaction                  tr;
    event                        gen_next_evt;
    mailbox #(transaction)       mon2scb_mbox;
    logic                  [7:0] expected_data;
    // flag
    bit                          first_flag     = 1;
    int                          pass_cnt       = 0;
    int                          fail_cnt       = 0;

    function new(mailbox#(transaction) mon2scb_mbox, event gen_next_evt);
        this.gen_next_evt = gen_next_evt;
        this.mon2scb_mbox = mon2scb_mbox;
    endfunction

    task run();
        forever begin
            mon2scb_mbox.get(tr);
            tr.debug_print("SCB");
            if (first_flag) begin
                first_flag = 0;
            end else begin
                // 4state comparison
                if (expected_data === tr.q) begin
                    $display("PASS");
                    pass_cnt++;
                end else begin
                    $display("FAIL");
                    fail_cnt++;
                end
            end
            expected_data = tr.d;

            ->gen_next_evt;
            $display(
                "=======================================================================================");
        end
    endtask
endclass

class environment;
    transaction            tr;
    generator              gen;
    driver                 drv;
    monitor                mon;
    scoreboard             scb;
    event                  gen_next_evt;
    event                  mon_next_evt;
    mailbox #(transaction) gen2drv_mbox;
    mailbox #(transaction) mon2scb_mbox;

    function new(virtual reg_interface reg_interface);
        gen2drv_mbox = new;
        mon2scb_mbox = new;
        gen          = new(gen2drv_mbox, gen_next_evt);
        drv          = new(gen2drv_mbox, reg_interface, mon_next_evt);
        mon          = new(mon2scb_mbox, reg_interface, mon_next_evt);
        scb          = new(mon2scb_mbox, gen_next_evt);
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
        // Print Pass Fail count
        $display("END REGISTER 8BIT VERIFICATION PROGRAM");
        $display("PASS : %d, FAIL : %d", scb.pass_cnt, scb.fail_cnt);
    endtask
endclass

module tb_register_8_sv_verification ();

    logic       clk;
    environment env;
    reg_interface reg_interface (clk);

    register_8 dut (
        .clk(clk),
        .rst(reg_interface.rst),
        .d  (reg_interface.d),
        .q  (reg_interface.q)
    );

    always #5 clk = ~clk;
    initial begin
        clk = 0;
        env = new(reg_interface);
        env.run(20);
        $finish;
    end
endmodule
