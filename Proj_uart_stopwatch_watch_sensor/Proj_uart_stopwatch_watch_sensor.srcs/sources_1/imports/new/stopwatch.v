`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/10/14 09:38:30
// Design Name: 
// Module Name: stopwatch
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module stopwatch #(
    parameter MSEC_BIT_WIDTH = 7,
    parameter SEC_BIT_WIDTH = 6,
    parameter MIN_BIT_WIDTH = 6,
    parameter HOUR_BIT_WIDTH = 5,
    parameter TIME_WIDTH = MSEC_BIT_WIDTH + SEC_BIT_WIDTH + MIN_BIT_WIDTH + HOUR_BIT_WIDTH
    )(
        input clk,
        input rst,
        input [3:0] btn,
        output [TIME_WIDTH-1:0] o_time
    );
    wire w_run_stop, w_clear, w_mode;
    wire [MSEC_BIT_WIDTH-1:0] w_live_msec;        
    wire [SEC_BIT_WIDTH-1:0]  w_live_sec;
    wire [MIN_BIT_WIDTH-1:0]  w_live_min;
    wire [HOUR_BIT_WIDTH-1:0] w_live_hour;

    wire [MSEC_BIT_WIDTH-1:0] w_msec;
    wire [SEC_BIT_WIDTH-1:0]  w_sec;
    wire [MIN_BIT_WIDTH-1:0]  w_min;
    wire [HOUR_BIT_WIDTH-1:0] w_hour;

    assign o_time = {w_hour, w_min, w_sec, w_msec};

    lap_module U_LAP_MODULE(
        .clk(clk),
        .rst(rst),
        .btn_lap(btn[3] & w_run_stop),
        .i_msec(w_live_msec),
        .i_sec(w_live_sec),
        .i_min(w_live_min),
        .i_hour(w_live_hour),
        .o_msec(w_msec),
        .o_sec(w_sec),
        .o_min(w_min),
        .o_hour(w_hour)
    );

    control_btn_unit U_CONTROL_UNIT(
        .clk(clk),
        .reset(rst),
        .btn_run_stop(btn[0]), // run_stop
        .btn_clear(btn[1]), // clear
        .btn_mode(btn[2]),  // mode
        .run_stop(w_run_stop),
        .clear(w_clear),
        .mode(w_mode)
    );

    stopwatch_datapath U_STOPWATCH_DATATPATH (
        .clk(clk),
        .rst(rst),
        .run_stop(w_run_stop),
        .clear(w_clear),
        .mode(w_mode),
        .msec(w_live_msec),
        .sec(w_live_sec),
        .min(w_live_min),
        .hour(w_live_hour)
    );
endmodule

module lap_module #(
    parameter MSEC_BIT_WIDTH = 7,
    parameter SEC_BIT_WIDTH = 6,
    parameter MIN_BIT_WIDTH = 6,
    parameter HOUR_BIT_WIDTH = 5,
    parameter HOLD_COUNT = 300_000_000
    )(
        input clk,
        input rst,
        input btn_lap,
        input [MSEC_BIT_WIDTH-1:0] i_msec,
        input [SEC_BIT_WIDTH-1:0]  i_sec,
        input [MIN_BIT_WIDTH-1:0]  i_min,
        input [HOUR_BIT_WIDTH-1:0] i_hour,
        output [MSEC_BIT_WIDTH-1:0] o_msec,
        output [SEC_BIT_WIDTH-1:0]  o_sec,
        output [MIN_BIT_WIDTH-1:0]  o_min,
        output [HOUR_BIT_WIDTH-1:0] o_hour
    );

    // display lap time when hold
    reg hold;
    reg [$clog2(HOLD_COUNT) - 1 : 0] hold_cnt;
    reg [MSEC_BIT_WIDTH-1:0] lap_msec;
    reg [SEC_BIT_WIDTH-1:0]  lap_sec;
    reg [MIN_BIT_WIDTH-1:0]  lap_min;
    reg [HOUR_BIT_WIDTH-1:0] lap_hour;

    always @(posedge clk, posedge rst) begin 
        if (rst) begin 
            hold <= 1'b0;
            hold_cnt <= 0;
            lap_msec <= 0;
            lap_sec <= 0;
            lap_min <= 0;
            lap_hour <= 0;
        end else if (btn_lap)begin 
            hold <= 1'b1;
            hold_cnt <= 0;
            lap_msec <= i_msec;
            lap_sec <= i_sec;
            lap_min <= i_min;
            lap_hour <= i_hour;
        end else if (hold) begin 
            if (hold_cnt == HOLD_COUNT - 1) begin 
                hold <= 1'b0;
                hold_cnt <= 0;
            end else begin 
                hold_cnt <= hold_cnt + 1;
            end
        end
    end

    assign o_msec = hold ? lap_msec : i_msec;
    assign o_sec = hold ? lap_sec : i_sec;
    assign o_min = hold ? lap_min : i_min;
    assign o_hour = hold ? lap_hour : i_hour;
endmodule

module stopwatch_datapath #(
    parameter MSEC_BIT_WIDTH = 7,
    parameter SEC_BIT_WIDTH = 6,
    parameter MIN_BIT_WIDTH = 6,
    parameter HOUR_BIT_WIDTH = 5
    )
    (
        input clk,
        input rst,
        input run_stop,
        input clear,
        input mode,
        output [MSEC_BIT_WIDTH - 1 :0] msec,
        output [SEC_BIT_WIDTH - 1:0] sec,
        output [MIN_BIT_WIDTH - 1:0] min,
        output [HOUR_BIT_WIDTH - 1:0] hour
    );

    wire w_tick_10ms, w_tick_sec, w_tick_min, w_tick_hour;

    sw_tick_gen_100hz U_TICK_GEN_100HMZ(
        .clk(clk),
        .rst(rst),
        .run_stop(run_stop),
        .clear(clear),
        .o_tick(w_tick_10ms)       // 100hz tick
    );

    sw_tick_counter #(.TIMES(100), .BIT_WIDTH(MSEC_BIT_WIDTH)) U_MSEC_COUNTER(
        .clk(clk),
        .rst(rst),
        .i_tick(w_tick_10ms),
        .clear(clear),
        .mode(mode),
        .time_count(msec), 
        .o_tick(w_tick_sec)
    );

    sw_tick_counter #(.TIMES(60), .BIT_WIDTH(SEC_BIT_WIDTH)) U_SEC_COUNTER(
        .clk(clk),
        .rst(rst),
        .i_tick(w_tick_sec),
        .clear(clear),
        .mode(mode),
        .time_count(sec), 
        .o_tick(w_tick_min)
    );

    sw_tick_counter #(.TIMES(60), .BIT_WIDTH(MIN_BIT_WIDTH)) U_MIN_COUNTER(
        .clk(clk),
        .rst(rst),
        .i_tick(w_tick_min),
        .clear(clear),
        .mode(mode),
        .time_count(min), 
        .o_tick(w_tick_hour)
    );

    sw_tick_counter #(.TIMES(24), .BIT_WIDTH(HOUR_BIT_WIDTH)) U_HOUR_COUNTER(
        .clk(clk),
        .rst(rst),
        .i_tick(w_tick_hour),
        .clear(clear),
        .mode(mode),
        .time_count(hour), 
        .o_tick()
    );
endmodule

module sw_tick_counter #(parameter TIMES = 100, BIT_WIDTH = 7)(
    input clk,
    input rst,
    input i_tick,
    input clear,
    input mode,
    output [BIT_WIDTH - 1 : 0] time_count, 
    output reg o_tick
    );

    reg [$clog2(TIMES) -1 : 0] counter_reg;
    assign time_count = counter_reg;

    always @(posedge clk, posedge rst) begin 
        if(rst | clear) begin 
            counter_reg <= 0;
            o_tick <= 1'b0;
        end else begin 
            if (mode) begin 
                // count down
                if (i_tick) begin 
                    counter_reg <= counter_reg - 1;
                    if (counter_reg == 0) begin 
                        counter_reg <= TIMES - 1;
                        o_tick <= 1'b1;
                    end
                end else begin 
                    o_tick <= 1'b0;
                end
            end else begin 
                // count up
                if (i_tick) begin 
                    counter_reg <= counter_reg + 1;
                    if (counter_reg == TIMES -1) begin 
                        counter_reg <= 0;
                        o_tick <= 1'b1;
                    end
                end else begin 
                    o_tick <= 1'b0;
                end
            end
        end
    end

endmodule

module sw_tick_gen_100hz(
    input clk,
    input rst,
    input run_stop,
    input clear,
    output reg o_tick       // 100hz tick
    );
    
    // 100 MHz -> 100Hz
    parameter F_COUNT = 1_000_000;
    reg [$clog2(F_COUNT)-1 : 0] counter_reg;

    always @(posedge clk, posedge rst) begin 
        if (rst | clear) begin 
            counter_reg <= 0;
            o_tick <= 1'b0;
        end else begin
            if(run_stop) begin 
                counter_reg <= counter_reg + 1;
                if (counter_reg == F_COUNT - 1) begin 
                    counter_reg <= 0;
                    o_tick <= 1'b1;
                end else begin 
                    o_tick <= 1'b0;
                end
            end else begin 
                o_tick <= 1'b0;
            end
        end
    end
endmodule