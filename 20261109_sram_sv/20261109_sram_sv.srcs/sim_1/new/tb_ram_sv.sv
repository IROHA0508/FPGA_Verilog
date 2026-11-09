`timescale 1ns / 1ps

interface ram_interface (
    input logic clk
);
    logic [5:0] addr;
    logic [7:0] wdata;
    logic       we;
    logic [7:0] rdata;
endinterface

class transaction;
    rand bit   [5:0] addr;
    rand bit   [7:0] wdata;
    rand bit         we;
    logic [7:0] rdata;

    function void debug_print(string name);
        $display("%t : [%s], addr = %d, wdata = %d, we = %d, rdata = %d",
                 $time, name, addr, wdata, we, rdata);
    endfunction
endclass

class generator;
    transaction tr;
    mailbox #(transaction) gen2drv_mbox;
    event gen_next_evt;

    function new(mailbox#(transaction) gen2drv_mbox, event gen_next_evt);
        this.gen2drv_mbox = gen2drv_mbox;
        this.gen_next_evt = gen_next_evt;
    endfunction

    task run(int run_count);
        repeat (run_count) begin
            tr = new;
            tr.randomize();
            gen2drv_mbox.put(tr);
            tr.debug_print("GEN");
            @(gen_next_evt);
        end
    endtask
endclass

class driver;
    transaction tr;
    mailbox #(transaction) gen2drv_mbox;
    event mon_next_evt;
    virtual ram_interface ram_interface_virtual;

    function new(mailbox#(transaction) gen2drv_mbox, event mon_next_evt,
                 virtual ram_interface ram_interface_virtual);
        this.gen2drv_mbox          = gen2drv_mbox;
        this.mon_next_evt          = mon_next_evt;
        this.ram_interface_virtual = ram_interface_virtual;
    endfunction

    task run();
        forever begin
            @(negedge ram_interface_virtual.clk);
            gen2drv_mbox.get(tr);
            ram_interface_virtual.addr  = tr.addr;
            ram_interface_virtual.wdata = tr.wdata;
            ram_interface_virtual.we    = tr.we;

            tr.debug_print("DRV");
            -> mon_next_evt;
        end
    endtask
endclass

class monitor;
    transaction tr;
    mailbox #(transaction) mon2scb_mbox;
    event mon_next_evt;
    virtual ram_interface ram_interface_virtual;

    function new(mailbox#(transaction) mon2scb_mbox, event mon_next_evt,
                 virtual ram_interface ram_interface_virtual);
        this.mon2scb_mbox          = mon2scb_mbox;
        this.mon_next_evt          = mon_next_evt;
        this.ram_interface_virtual = ram_interface_virtual;
    endfunction

    task run();
        forever begin
            @(mon_next_evt);
            @(posedge ram_interface_virtual.clk);
            #1;
            tr = new;
            tr.addr  = ram_interface_virtual.addr;
            tr.wdata = ram_interface_virtual.wdata;
            tr.we    = ram_interface_virtual.we;
            tr.rdata = ram_interface_virtual.rdata;
            mon2scb_mbox.put(tr);
            tr.debug_print("MON");
        end
    endtask
endclass

class scoreboad;
    transaction tr;
    mailbox #(transaction) mon2scb_mbox;
    event gen_next_evt;

    function new(mailbox#(transaction) mon2scb_mbox, event gen_next_evt);
        this.mon2scb_mbox = mon2scb_mbox;
        this.gen_next_evt = gen_next_evt;
    endfunction

    logic [7:0] expected_buffer[0:64 - 1];
    int   total_cnt                  = 0;
    int   pass_cnt                   = 0;
    int   fail_cnt                   = 0;
    task run();
        forever begin
            mon2scb_mbox.get(tr);
            tr.debug_print("SCB");
            total_cnt++;
            if (tr.we) begin
                // save read data to buffer
                expected_buffer[tr.addr] = tr.wdata;
            end else begin
                if (expected_buffer[tr.addr] === tr.rdata) begin
                    $display("PASS");
                    pass_cnt++;
                end else begin
                    $display("FAIL");
                    fail_cnt++;
                    $display("Expected data : %d, Read Data : %d",
                             expected_buffer[tr.addr], tr.rdata);
                end
            end

            ->gen_next_evt;
        end
    endtask

    task report();
        $display("******************************");
        $display("total count : %d", total_cnt);
        $display("pass count : %d", pass_cnt);
        $display("fail count : %d", fail_cnt);
        $display("******************************");
    endtask
endclass

class environment;
    generator gen;
    driver drv;
    monitor mon;
    scoreboad scb;

    mailbox #(transaction) gen2drv_mbox;
    mailbox #(transaction) mon2scb_mbox;

    event gen_next_evt;
    event mon_next_evt;

    function new(virtual ram_interface ram_interface_virtual);
        gen2drv_mbox = new;
        mon2scb_mbox = new;

        gen = new(gen2drv_mbox, gen_next_evt);
        drv = new(gen2drv_mbox, mon_next_evt, ram_interface_virtual);
        mon = new(mon2scb_mbox, mon_next_evt, ram_interface_virtual);
        scb = new(mon2scb_mbox, gen_next_evt);
    endfunction

    task run(int run_count);
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

module tb_ram_sv ();
    logic clk = 0;
    ram_interface ram_interface (clk);
    environment env;


    ram_ip_sv dut (
        .clk  (clk),
        .addr (ram_interface.addr),
        .wdata(ram_interface.wdata),
        .we   (ram_interface.we),
        .rdata(ram_interface.rdata)
    );

    always #5 clk = ~clk;

    initial begin
        env = new(ram_interface);
        env.run(500);
        $finish;
    end
endmodule
