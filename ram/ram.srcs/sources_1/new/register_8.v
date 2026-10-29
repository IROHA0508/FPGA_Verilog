`timescale 1ns / 1ps

module register_8(
        input clk,
        input rst,
        input [7:0] din,
        output [7:0] q
    );

    reg [7:0] q_reg;
    assign q = q_reg;

    always @(posedge clk, posedge rst) begin 
        if(rst) begin 
            q_reg <= 0;
        end else begin 
            q_reg <= din;
        end
    end

endmodule
