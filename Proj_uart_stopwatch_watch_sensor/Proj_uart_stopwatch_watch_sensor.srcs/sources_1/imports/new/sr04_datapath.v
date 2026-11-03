
`timescale 1ns / 1ps

module sr04_datapath (
    input clk,
    input rst,
    input us_tick,
    input echo_cnt_en,
    input echo_cnt_clear,
    input done,

    output reg [15:0] distance
);

    // Echo HIGH duration counter (1us unit)
    reg [15:0] echo_cnt;

    // Distance calculation
    wire [15:0] distance_calc;

    assign distance_calc = echo_cnt / 16'd58;

    //========================================
    // 1. Echo Counter
    //========================================
    always @(posedge clk or posedge rst) begin
        if (rst)
            echo_cnt <= 16'd0;
        else if (echo_cnt_clear)
            echo_cnt <= 16'd0;
        else if (echo_cnt_en && us_tick)
            echo_cnt <= echo_cnt + 1'b1;
    end

    //========================================
    // 2. Distance Register
    //========================================
    always @(posedge clk or posedge rst) begin
        if (rst)
            distance <= 16'd0;
        else if (done)
            distance <= distance_calc;
    end

endmodule
