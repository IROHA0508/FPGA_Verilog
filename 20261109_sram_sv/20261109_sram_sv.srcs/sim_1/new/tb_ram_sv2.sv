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
    rand bit [5:0] addr;
    rand bit [7:0] wdata;
    rand bit       we;
    logic    [7:0] rdata;

    function void debug_print(string name);
        $display("%t : [%s], addr = %d, wdata = %d, we = %d, rdata = %d",
                 $time, name, addr, wdata, we, rdata);
    endfunction
endclass

class generator;
    transaction tr;
    mailbox #(transaction) gen2drv_mbox;
    event gen_next_evt;
    // ADD
    mailbox #(transaction) gen2scb_mbox;

    function new(mailbox#(transaction) gen2drv_mbox,
                 mailbox#(transaction) gen2scb_mbox, event gen_next_evt);
        this.gen2drv_mbox = gen2drv_mbox;
        this.gen2scb_mbox = gen2scb_mbox;
        this.gen_next_evt = gen_next_evt;
    endfunction

    task run(int run_count);
        repeat (run_count) begin
            tr = new;
            tr.randomize();
            gen2drv_mbox.put(tr);
            // ADD
            gen2scb_mbox.put(tr);
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
            ->mon_next_evt;
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
    transaction tr_mon;
    transaction tr_gen;
    mailbox #(transaction) mon2scb_mbox;
    mailbox #(transaction) gen2scb_mbox;
    event gen_next_evt;

    function new(mailbox#(transaction) mon2scb_mbox,
                 mailbox#(transaction) gen2scb_mbox, event gen_next_evt);
        this.mon2scb_mbox = mon2scb_mbox;
        this.gen2scb_mbox = gen2scb_mbox;
        this.gen_next_evt = gen_next_evt;
    endfunction

    logic [7:0] expected_buffer[0:64 - 1];
    int         total_cnt                  = 0;
    int         pass_cnt                   = 0;
    int         fail_cnt                   = 0;
    int         skip_cnt                   = 0;
    int         write_cnt                  = 0;
    bit         written        [0:  64-1];
    task run();
        forever begin
            mon2scb_mbox.get(tr_mon);
            tr_mon.debug_print("SCB - tr_mon");
            // ADD
            gen2scb_mbox.get(tr_gen);
            tr_gen.debug_print("SCB - tr_gen");
            total_cnt++;

            // (1) gen이 의도한 입력과 monitor가 본 입력이 같은지 전체 비교
            if (tr_gen.addr !== tr_mon.addr || tr_gen.wdata !== tr_mon.wdata ||
                tr_gen.we !== tr_mon.we) begin
                $display("FAIL : GEN/MON mismatch");
                fail_cnt++;
            end

            // (2) 기대값은 gen 기준으로만 갱신하고, 읽기일 때 비교
            if (tr_gen.we) begin
                expected_buffer[tr_gen.addr] = tr_gen.wdata;
                written[tr_gen.addr]         = 1;
                write_cnt++;
            end else begin
                if (expected_buffer[tr_gen.addr] === tr_mon.rdata) begin
                    $display("PASS");
                    pass_cnt++;
                end else if (!written[tr_gen.addr]) begin
                    skip_cnt++;
                    $display("SKIP (unwritten addr)");
                end else begin
                    $display("FAIL");
                    fail_cnt++;
                    $display("Expected data : %d, Read Data : %d",
                             expected_buffer[tr_gen.addr], tr_mon.rdata);
                end
            end
            ->gen_next_evt;
        end
    endtask

    task report();
        $display("******************************");
        $display("total count : %d", total_cnt);
        $display("write count : %d", write_cnt);
        $display("pass count : %d", pass_cnt);
        $display("skip count : %d", skip_cnt);
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
    mailbox #(transaction) gen2scb_mbox;
    mailbox #(transaction) mon2scb_mbox;

    event gen_next_evt;
    event mon_next_evt;

    function new(virtual ram_interface ram_interface_virtual);
        gen2drv_mbox = new;
        mon2scb_mbox = new;
        // ADD
        gen2scb_mbox = new;

        gen = new(gen2drv_mbox, gen2scb_mbox, gen_next_evt);
        drv = new(gen2drv_mbox, mon_next_evt, ram_interface_virtual);
        mon = new(mon2scb_mbox, mon_next_evt, ram_interface_virtual);
        scb = new(mon2scb_mbox, gen2scb_mbox, gen_next_evt);
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

module tb_ram_sv2 ();
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
