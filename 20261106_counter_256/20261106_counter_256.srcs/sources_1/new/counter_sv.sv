`timescale 1ns / 1ps

module counter_sv (
    input  logic       clk,
    input  logic       rst,
    input  logic       mode,
    input  logic       run_stop,
    input  logic       clear,
    output logic [7:0] counter
);

    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            counter <= 0;
        end else if (clear) begin       // 동기 clear
            counter <= 0;
        end else if (run_stop) begin
            if (mode) counter <= counter - 1;
            else      counter <= counter + 1;
        end
    end
endmodule
