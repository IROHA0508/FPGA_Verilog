`timescale 1ns / 1ps

module ram_ip_sv (
    input  logic       clk,
    input  logic [5:0] addr,
    input  logic [7:0] wdata,
    input  logic       we,
    output logic [7:0] rdata
);
    // [칸 하나의 bit 폭] 이름 [칸의 크기]
    logic [7:0] ram[0:64-1];

    always_ff @(posedge clk) begin
        if (we) begin
            ram[addr] <= wdata;
        end
    end

    assign rdata = ram[addr];
endmodule
