`timescale 1ns / 1ps

// Sequential Output
module bram_ip(
        input clk,
        input we,
        input [7:0] addr,
        input [7:0] wdata,
        output reg [7:0] rdata
    );

    reg [7:0] ram [0:255];

    always @(posedge clk) begin 
        if (we) ram[addr] <= wdata;
        // Sequential Output
        else rdata <= ram[addr];
    end
endmodule

// Combinational Output
// module bram_ip(
//         input clk,
//         input we,
//         input [7:0] addr,
//         input [7:0] wdata,
//         output [7:0] rdata
//     );

//     reg [7:0] ram [0:255];

//     always @(posedge clk) begin 
//         if (we) ram[addr] <= wdata;
//     end

//     // Combinational Output
//     assign rdata = ram[addr];

// endmodule
