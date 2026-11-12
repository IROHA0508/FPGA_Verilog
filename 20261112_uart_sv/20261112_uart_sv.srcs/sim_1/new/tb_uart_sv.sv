`timescale 1ns / 1ps


interface uart_interface (
    input clk
);
    logic       rst;
    logic       tx_start;
    logic [7:0] tx_data;
    logic       tx_busy;
    logic       tx;
endinterface

class transaction;
    // input
    bit            rst;
    bit            tx_start;
    rand bit [7:0] tx_data;

    rand int       interval;  // tx start interval

    // output
    logic          tx_busy;
    logic          tx;

    constraint interval_range {interval < (100_000_000 / 9600);}

    function debug_print(string name);
        $display(
            "%t : [%s] rst = %d, tx_start = %d, tx_data = %d, interval = %d, tx_busy = %d, tx = %d",
            $time, name, rst, tx_start, tx_data, interval, tx_busy, tx);
    endfunction
endclass

class generator;
    transaction         tr;
    event               gen_next_evt;
    mail #(transaction) gen2drv_mbox;

    function new(mailbox#(transaction) gen2drv_mbox, event gen_next_evt);
        this.gen2drv_mbox = gen2drv_mbox;
        this.gen_next_evt = gen_next_evt;
    endfunction

    task run(int run_count);
        repeat (run_count) begin
            tr = new;
            tr.randomize();
            tr.rst = 0;
            tr.tx_start = 0;
            gen2drv_mboxput(tr);
            @(gen_next_evt);
        end
    endtask
endclass

class driver;
    transaction            tr;
    mailbox #(transaction) gen2drv_mbox;
    virtual uart_interface uart_interface_virtual;

    function new(mailbox#(transaction) gen2drv_mbox,
                 virtual uart_interface uart_interface_virtual);
        this.gen2drv_mbox           = gen2drv_mbox;
        this.uart_interface_virtual = uart_interface_virtual;
    endfunction

    int busy_check_count = 0;

    task run();
        forever begin
            @(negedge uart_interface_virtual.clk);
            busy_check_count = 0;
            gen2drv_mbox.get(tr);
            while (!uart_interface_virtual.tx_busy) begin
                @(negedge uart_interface_virtual.clk);
                busy_check_count++;

                if (busy_check_count > (100_000_000 / 9600) * 10) begin
                    $display("tx_busy high too long");
                    break;
                end
            end

            if (!uart_interface_virtual.tx_busy) begin
                uart_interface_virtual.start   = 1;
                uart_interface_virtual.rst     = 0;
                uart_interface_virtual.tx_data = tr.tx_data;

                @(negedge uart_interface_virtual.clk);
                uart_interface_virtual.start    = 0;
                uart_interface_virtual.tx_data  = 8'bxx;

                uart_interface_virtual.tx_start = tr.tx_start;
            end
            ->mon_next_evt;
        end
    endtask
endclass

class monitor;
    transaction            tr_in;
    transaction            tr_out;
    mailbox #(transaction) mon2scb_mbox_in;
    mailbox #(transaction) mon2scb_mbox_out;
    virtual uart_interface uart_interface_virtual;

    function new(mailbox#(transaction) mon2scb_mbox_in,
                 mailbox#(transaction) mon2scb_mbox_out,
                 virtual uart_interface uart_interface_virtual);
        this.mon2scb_mbox_in        = mon2scb_mbox_in;
        this.mon2scb_mbox_out       = mon2scb_mbox_out;
        this.uart_interface_virtual = uart_interface_virtual;
    endfunction

    task uart_receive(output logic [7:0] receive_data);
        @(posedge uart_interface_virtual.clk);
        #((100_000_000 / 9600) / 2);

        for (int i = 0; i < 8; i++) begin
            receive_data[i] = uart_interface_virtual.tx;
            #(100_000_000 / 9600);
        end

        #(100_000_000 / 9600);
        #((100_000_000 / 9600) / 2);
    endtask

    task run();
        forever begin
            // 1. check start == 1
            @(posedge uart_interface_virtual.clk);
            while (uart_interface_virtual.tx_start) begin
                @(posedge uart_interface_virtual.clk);
            end

            // 2. mon2scb_mbox_in put
            tr_in         = new;
            tr_in.tx_data = uart_interface_virtual.tx_data;
            // tr_in.rx       = uart_interface_virtual.rx;
            // tr_in.tx_start = uart_interface_virtual.tx_start;
            // tr_in.tx       = uart_interface_virtual.tx;
            // tr_in.tx_busy  = uart_interface_virtual.tx_busy;
            mon2scb_mbox_in.get(tr_in);

            // 3. baud_time * 10 , mon2scb_mbox_out put
            tr_out = new;
            uart_receive(tr_out.tx_data);
            tr_out.rst      = uart_interface_virtual.rst;
            tr_out.tx       = uart_interface_virtual.tx;
            tr_out.tx_busy  = uart_interface_virtual.tx_busy;

            mon2scb_mbox_in.get(tr_out);
        end
    endtask
endclass

class scoreboard;
    transaction            tr_in;
    transaction            tr_out;
    event                  gen_next_evt;
    mailbox #(transaction) mon2scb_mbox_in;
    mailbox #(transaction) mon2scb_mbox_out;

    function new(mailbox#(transaction) mon2scb_mbox_in,
                 mailbox#(transaction) mon2scb_mbox_out, event gen_next_evt);
        this.mon2scb_mbox_in = mon2scb_mbox_in;
        this.mon2scb_mbox_out = mon2scb_mbox_out;
        this.gen_next_evt = gen_next_evt;
    endfunction
endclass

class environment;
    generator              gen;
    driver                 drv;
    monitor                mon;
    scoreboard             scb;

    mailbox #(transaction) gen2drv_mbox;
    mailbox #(transaction) mon2scb_mbox_in;
    mailbox #(transaction) mon2scb_mbox_out;

    event                  gen_next_evt;

    function new(virtual uart_interface uart_interface_virtual);
        gen2drv_mbox = new;
        mon2scb_mbox_in = new;
        mon2scb_mbox_out = new;

        gen = new(gen2drv_mbox, gen_next_evt);
        drv = new(gen2drv_mbox, uart_interface_virtual);
        mon = new(mon2scb_mbox_in, mon2scb_mbox_out, uart_interface_virtual);
        scb = new(mon2scb_mbox_in, mon2scb_mbox_out, gen_next_evt);
    endfunction
endclass

module tb_uart_sv ();
    parameter BAUD_TIME = (100_100_100 / 9600) * 10;
    logic clk = 0;

    environment env;

    uart_interface uart_if (clk);

    uart_sv dut (
        .clk     (clk),
        .rst     (uart_if.rst),
        .tx_start(uart_if.tx_start),
        .tx_data (uart_if.tx_data),
        .tx_busy (uart_if.tx_busy),
        .tx      (uart_if.tx)
    );

    always #5 clk = ~clk;

    initial begin
        env = new(uart_if);
        $finish;
    end
endmodule
