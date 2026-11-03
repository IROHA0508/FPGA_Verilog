
`timescale 1ns / 1ps

module us_tick_gen #(
    parameter F_COUNT = 100
)(
    input clk,
    input rst,
    output reg us_tick
);

    reg [31:0] count;

    //========================================
    // 1us Tick Generator
    //========================================
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            count   <= 0;
            us_tick <= 1'b0;
        end
        else begin
            if (count == F_COUNT - 1) begin
                count   <= 0;
                us_tick <= 1'b1;
            end
            else begin
                count   <= count + 1'b1;
                us_tick <= 1'b0;
            end
        end
    end

endmodule
