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
    bit                     rst;
    bit                     tx_start;
    rand logic        [7:0] tx_data;

    rand int unsigned       interval;  // tx start interval

    // error check bit
    bit                     start_bit_error;
    bit                     stop_bit_error;
    bit                     frame_time_error;
    
    // output
    logic                   tx_busy;
    logic                   tx;

    constraint interval_range {interval < (100_000_000 / 9600);}

    function debug_print(string name);
        $display(
            "%t : [%s] rst = %d, tx_start = %d, tx_data = %d, interval = %d, tx_busy = %d, tx = %d",
            $time, name, rst, tx_start, tx_data, interval, tx_busy, tx);
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
            tr = new;
            tr.randomize();
            tr.rst = 0;
            tr.tx_start = 0;
            gen2drv_mbox.put(tr);
            tr.debug_print("GEN");
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

    task reset();
        uart_interface_virtual.rst      = 1;
        uart_interface_virtual.tx_data  = 0;
        uart_interface_virtual.tx_start = 0;
        repeat (2) @(negedge uart_interface_virtual.clk);
        uart_interface_virtual.rst = 0;
    endtask

    task run();
        forever begin
            @(negedge uart_interface_virtual.clk);
            busy_check_count = 0;
            gen2drv_mbox.get(tr);

            while (uart_interface_virtual.tx_busy) begin
                @(negedge uart_interface_virtual.clk);
                busy_check_count++;

                if (busy_check_count > (100_000_000 / 9600) * 10) begin
                    $display("tx_busy high too long");
                    break;
                end
            end

            if (!uart_interface_virtual.tx_busy) begin
                repeat (tr.interval) @(negedge uart_interface_virtual.clk);
                uart_interface_virtual.rst      = 0;
                uart_interface_virtual.tx_start = 1;
                uart_interface_virtual.tx_data  = tr.tx_data;

                @(negedge uart_interface_virtual.clk);

                uart_interface_virtual.tx_start = 0;
                uart_interface_virtual.tx_data  = 8'bxx;
            end
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

    localparam BAUD_TIME = (100_000_000 / 9600) * 10;
    time start_time;
    time current_time;
    time frame_start_time;
    time frame_end_time;

    task uart_receive(output logic [7:0] receive_data);
        // @(posedge uart_interface_virtual.clk);
        // @(negedge uart_interface_virtual.tx);

        // start bit error checker
        @ (!uart_interface_virtual.tx);
        start_time       = $time;
        frame_start_time = start_time;
        current_time     = start_time;

        while ( uart_interface_virtual.tx == 0 && (current_time - start_time) <= BAUD_TIME ) begin
            @(posedge uart_interface_virtual.clk);
            current_time = $time;
        end
        $display("START BIT TIME : %tns", (current_time - start_time)/1000);
        if ((current_time - start_time) >= (BAUD_TIME * (15 / 16))) begin
            tr_out.start_bit_error = 0;
        end else begin
            tr_out.start_bit_error = 1;
        end

        // #(BAUD_TIME / 2);

        // DATA STATE START
        for (int i = 0; i < 8; i++) begin
            #(BAUD_TIME / 2);
            receive_data[i] = uart_interface_virtual.tx;
            #(BAUD_TIME / 2);
        end
        // #(BAUD_TIME);
        // #(BAUD_TIME / 2);

        // wait before STOP state
        start_time   = $time;
        current_time = start_time;
        while (uart_interface_virtual.tx == 0 && (current_time - start_time) <= BAUD_TIME/2) begin
            @(posedge uart_interface_virtual.clk);
            current_time = $time;
        end

        if ((current_time - start_time) >= (BAUD_TIME / 2)) begin
            tr_out.stop_bit_error = 1;
        end else begin
            // stop bit error checker
            start_time   = $time;
            current_time = start_time;
            while ( uart_interface_virtual.tx == 1 && (current_time - start_time) <= BAUD_TIME && (uart_interface_virtual.tx_busy == 1)) begin
                @(posedge uart_interface_virtual.clk);
                current_time = $time;
            end
            $display("END BIT TIME : %tns", (current_time - start_time)/1000);
            if ((current_time - start_time) >= (BAUD_TIME * (15 / 16))) begin
                tr_out.stop_bit_error = 0;
            end else begin
                tr_out.stop_bit_error = 1;
            end
        end

        // frame time check
        frame_end_time = $time;
        $display("FRAME TIME : %tns", (frame_end_time - frame_start_time)/1000);
        if ((frame_end_time - frame_start_time >= (BAUD_TIME * 9.5)) && (frame_end_time - frame_start_time <= (BAUD_TIME * 10.5))) begin 
            tr_out.frame_time_error = 0;
        end else begin 
            tr_out.frame_time_error = 1;
        end
    endtask

    task run();
        forever begin
            // 1. check start == 1
            @(posedge uart_interface_virtual.clk);
            while (!uart_interface_virtual.tx_start) begin
                @(posedge uart_interface_virtual.clk);
            end

            // 2. mon2scb_mbox_in put
            tr_in         = new;
            tr_in.tx_data = uart_interface_virtual.tx_data;
            // tr_in.rx       = uart_interface_virtual.rx;
            // tr_in.tx_start = uart_interface_virtual.tx_start;
            // tr_in.tx       = uart_interface_virtual.tx;
            // tr_in.tx_busy  = uart_interface_virtual.tx_busy;
            mon2scb_mbox_in.put(tr_in);
            tr_in.debug_print("MON tr_in");

            // 3. baud_time * 10 , mon2scb_mbox_out put
            tr_out = new;
            uart_receive(tr_out.tx_data);
            tr_out.rst     = uart_interface_virtual.rst;
            tr_out.tx      = uart_interface_virtual.tx;
            tr_out.tx_busy = uart_interface_virtual.tx_busy;

            mon2scb_mbox_out.put(tr_out);
            tr_out.debug_print("MON tr_out");
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

    int total_cnt         = 0;
    int tx_data_pass_cnt  = 0;
    int tx_data_fail_cnt  = 0;
    int tx_start_pass_cnt = 0;
    int tx_start_fail_cnt = 0;
    int tx_stop_pass_cnt = 0;
    int tx_stop_fail_cnt = 0;
    int tx_frame_pass_cnt = 0;
    int tx_frame_fail_cnt = 0;

    task run();
        forever begin
            mon2scb_mbox_in.get(tr_in);
            total_cnt++;
            tr_in.debug_print("SCB tr in");

            mon2scb_mbox_out.get(tr_out);
            tr_out.debug_print("SCB tr out");

            // TX start bit error check
            if (tr_out.start_bit_error) begin
                tx_start_fail_cnt++;
                $display("START FRAME FAIL");
            end else begin
                tx_start_pass_cnt++;
                $display("START FRAME PASS");
            end

            if (tr_in.tx_data === tr_out.tx_data) begin
                tx_data_pass_cnt++;
                $display("tx_data PASS");
            end else begin
                tx_data_fail_cnt++;
                $display("tx_data FAIL");
            end

            // TX stop bit error check
            if (tr_out.stop_bit_error) begin
                tx_stop_fail_cnt++;
                $display("STOP FRAME FAIL");
            end else begin
                tx_stop_pass_cnt++;
                $display("STOP FRAME PASS");
            end

            // TX frame bit error check
            if (tr_out.frame_time_error) begin
                tx_frame_fail_cnt++;
                $display("FRAME TIME FAIL");
            end else begin
                tx_frame_pass_cnt++;
                $display("FRAME TIME PASS");
            end
            ->gen_next_evt;
        end
    endtask

    task report();
        $display("=====================================");
        $display("TOTAL COUNT : %4d", total_cnt);
        $display("TX DATA PASS : %4d", tx_data_pass_cnt);
        $display("TX DATA FAIL : %4d", tx_data_fail_cnt);
        $display("TX START PASS : %4d", tx_start_pass_cnt);
        $display("TX START FAIL : %4d", tx_start_fail_cnt);
        $display("TX STOP PASS : %4d", tx_stop_pass_cnt);
        $display("TX STOP FAIL : %4d", tx_stop_fail_cnt);
        $display("TX FRAME PASS : %4d", tx_frame_pass_cnt);
        $display("TX FRAME FAIL : %4d", tx_frame_fail_cnt);
        $display("=====================================");
    endtask
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
        env.run(2);
        $finish;
    end
endmodule
