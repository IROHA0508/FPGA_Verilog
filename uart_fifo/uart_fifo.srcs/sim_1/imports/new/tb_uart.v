`timescale 1ns / 1ps

module tb_uart();
    parameter BAUD_BIT_PERIOD = 100_000_000 / 9600 * 10;

    reg clk, rst, btnR;
    wire led, tx;

    uart dut(
        .clk(clk),
        .rst(rst),
        .btnR(btnR),
        .led(led),     // tx busy
        .tx(tx)
    );

    // generate 10ns clock
    always #5 clk = ~clk;

    initial begin 
        clk = 0;
        rst = 1;
        btnR = 0;
        #10 rst = 0;

        // push button tx_start
        btnR = 1;
        #(10 * 100 * 10);
        btnR = 0;

        // tx : START + Data[7:0] + STOP
        #(BAUD_BIT_PERIOD * 10);

        #100;
        $stop;

    end
endmodule
