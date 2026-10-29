`timescale 1ns / 1ps

module tb_ram();
    reg clk, we;
    reg [7:0] addr, wdata;
    
    wire [7:0] rdata;

    bram_ip dut(
        .clk(clk),
        .we(we),
        .addr(addr),
        .wdata(wdata),
        .rdata(rdata)
    );

    always #5 clk = ~clk;

    initial begin 
        clk = 0;
        we = 0;
        addr = 8'b0;
        wdata = 8'b0;

        // delay 1 clk
        @(negedge clk); 
        we = 1;
        addr = 10;
        wdata = 8'h0a;

        // delay 1 clk
        @(negedge clk); 
        addr = 11;
        wdata = 8'h0b;

        // delay 1 clk
        @(negedge clk); 
        addr = 31;
        wdata = 8'h0c;

        // delay 1 clk
        @(negedge clk); 
        addr = 32;
        wdata = 8'h0d;

        @(negedge clk); 
        
        // delay 1 clk
        @(negedge clk); 
        we = 0;

        @(negedge clk); 
        addr = 10;
        
        // delay 1 clk
        @(negedge clk); 
        addr = 11; 
        
        // delay 1 clk
        @(negedge clk); 
        addr = 31;
        
        // delay 1 clk
        @(negedge clk); 
        addr = 32;

        @(negedge clk);
        $stop;
        
    end
endmodule
