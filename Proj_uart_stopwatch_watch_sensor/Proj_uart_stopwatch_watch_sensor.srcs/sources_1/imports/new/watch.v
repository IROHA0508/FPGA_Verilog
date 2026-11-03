`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/10/14 16:27:07
// Design Name: 
// Module Name: watch
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


module watch    #(
    parameter MSEC_BIT_WIDTH = 7,
    parameter SEC_BIT_WIDTH = 6,
    parameter MIN_BIT_WIDTH = 6,
    parameter HOUR_BIT_WIDTH = 5,
    parameter TIME_WIDTH = MSEC_BIT_WIDTH + SEC_BIT_WIDTH + MIN_BIT_WIDTH + HOUR_BIT_WIDTH
    )(
        input clk,
        input rst,
        input [3:0] btn,
        input sw0, sw2,
        output [TIME_WIDTH-1:0] o_time,
        output [1:0] disp_mode,
        output [2:0] set_field,
        output blink_en
    );
    wire w_watch_run, w_set_active, w_inc, w_dec;
    wire [MSEC_BIT_WIDTH-1:0] w_msec;
    wire [SEC_BIT_WIDTH-1:0]  w_sec;
    wire [MIN_BIT_WIDTH-1:0]  w_min;
    wire [HOUR_BIT_WIDTH-1:0] w_hour;

    assign o_time = {w_hour, w_min, w_sec, w_msec};
    
    set_time U_SET_TIME(
        .clk(clk), 
        .rst(rst), 
        .sw0(sw0), 
        .sw2(sw2),
        .btnR(btn[0]), 
        .btnL(btn[1]), 
        .btnU(btn[2]), 
        .btnD(btn[3]),   
        .watch_run(w_watch_run), 
        .set_active(w_set_active),
        .set_field(set_field),
        .disp_mode(disp_mode),
        .blink_en(blink_en), 
        .inc(w_inc), 
        .dec(w_dec)
    );

    watch_datapath U_WATCH_DATATPATH (
        .clk(clk),
        .rst(rst),
        .run_stop(w_watch_run),
        .clear(1'b0),
        .inc(w_inc),
        .dec(w_dec),
        .set_field(set_field),
        .msec(w_msec),
        .sec(w_sec),
        .min(w_min),
        .hour(w_hour)
    );

endmodule

module watch_datapath #(
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
        input inc,
        input dec,
        input [2:0] set_field,
        output [MSEC_BIT_WIDTH - 1 :0] msec,
        output [SEC_BIT_WIDTH - 1:0] sec,
        output [MIN_BIT_WIDTH - 1:0] min,
        output [HOUR_BIT_WIDTH - 1:0] hour
    );

    wire w_tick_10ms, w_tick_sec, w_tick_min, w_tick_hour;
    wire w_inc_sec, w_inc_min, w_inc_hour;
    wire w_dec_sec, w_dec_min, w_dec_hour;

    // assign w_inc_ms   = inc && (set_field == 3'b100);
    assign w_inc_sec  = inc && (set_field == 3'b101);
    assign w_inc_min  = inc && (set_field == 3'b110);
    assign w_inc_hour = inc && (set_field == 3'b111);

    // assign w_dec_ms   = dec && (set_field == 3'b100);
    assign w_dec_sec  = dec && (set_field == 3'b101);
    assign w_dec_min  = dec && (set_field == 3'b110);
    assign w_dec_hour = dec && (set_field == 3'b111);

    w_tick_gen_100hz U_TICK_GEN_100HMZ(
        .clk(clk),
        .rst(rst),
        .run_stop(run_stop),
        .clear(clear),
        .o_tick(w_tick_10ms)       // 100hz tick
    );

    w_tick_counter #(.TIMES(100), .BIT_WIDTH(MSEC_BIT_WIDTH)) U_MSEC_COUNTER(
        .clk(clk),
        .rst(rst),
        .i_tick(w_tick_10ms),
        .inc(1'b0),
        .dec(1'b0),
        .time_count(msec), 
        .o_tick(w_tick_sec)
    );

    w_tick_counter #(.TIMES(60), .BIT_WIDTH(SEC_BIT_WIDTH)) U_SEC_COUNTER(
        .clk(clk),
        .rst(rst),
        .i_tick(w_tick_sec),
        .inc(w_inc_sec),
        .dec(w_dec_sec),
        .time_count(sec), 
        .o_tick(w_tick_min)
    );

    w_tick_counter #(.TIMES(60), .BIT_WIDTH(MIN_BIT_WIDTH)) U_MIN_COUNTER(
        .clk(clk),
        .rst(rst),
        .i_tick(w_tick_min),
        .inc(w_inc_min),
        .dec(w_dec_min),
        .time_count(min), 
        .o_tick(w_tick_hour)
    );

    w_tick_counter #(.TIMES(24), .BIT_WIDTH(HOUR_BIT_WIDTH), .INIT_VALUE(12)) U_HOUR_COUNTER(
        .clk(clk),
        .rst(rst),
        .i_tick(w_tick_hour),
        .inc(w_inc_hour),
        .dec(w_dec_hour),
        .time_count(hour), 
        .o_tick()
    );
endmodule

module set_time(
        input clk,
        input rst,
        input sw0,           // 0: watch, 1: stopwatch
        input sw2,           // 1: time set mode
        input btnL,          
        input btnR,
        input btnU,
        input btnD,
        output reg watch_run,
        output reg set_active,
        output reg [2:0] set_field,
        output reg [1:0] disp_mode,
        output reg blink_en,
        output reg inc,
        output reg dec
    );

    parameter IDLE = 0, SET_SEC = 1, SET_MIN = 2, SET_HOUR = 3;
    reg [1:0] c_state, n_state;

    
    // state SL
    always @(posedge clk, posedge rst) begin 
        if (rst) begin 
            c_state <= IDLE;
        end else begin 
            c_state <= n_state;
        end
    end

    // next output CL
    wire set_en = ~sw0 && sw2;
    always @(*) begin 

        case(c_state) 
            IDLE : begin  
                watch_run = 1;
                set_active = 0;
                set_field = 3'b000;
                disp_mode = 2'b00;
                blink_en = 0;
                inc = 0;
                dec = 0;
                if (set_en) begin 
                    n_state = SET_SEC;
                end else begin 
                    n_state = IDLE;
                end
            end

            SET_SEC : begin 
                watch_run = 0;
                set_active = 1;
                set_field = 3'b101;
                disp_mode = 2'b10;
                blink_en = 1;
                inc = 0;
                dec = 0;
                if (set_en) begin 
                    if (btnU) begin 
                        n_state = SET_SEC;
                        inc = 1;
                    end else if (btnD) begin 
                        n_state = SET_SEC;
                        dec = 1;
                    end else if (btnL) begin 
                        n_state = SET_MIN;
                    end else if (btnR) begin 
                        n_state = SET_HOUR;
                    end else begin 
                        n_state = SET_SEC;
                    end
                end else begin 
                    // escape when set_en = 0
                    n_state = IDLE;
                end
            end

            SET_MIN : begin 
                watch_run = 0;
                set_active = 1;
                set_field = 3'b110;
                disp_mode = 2'b11;
                blink_en = 1;
                inc = 0;
                dec = 0;
                if (set_en) begin 
                    if (btnU) begin 
                        n_state = SET_MIN;
                        inc = 1;
                    end else if (btnD) begin 
                        n_state = SET_MIN;
                        dec = 1;
                    end else if (btnL) begin 
                        n_state = SET_HOUR;
                    end else if (btnR) begin 
                        n_state = SET_SEC;
                    end else begin 
                        n_state = SET_MIN;
                    end
                end else begin 
                    // escape when set_en = 0
                    n_state = IDLE;
                end
            end

            SET_HOUR : begin 
                watch_run = 0;
                set_active = 1;
                set_field = 3'b111;
                disp_mode = 2'b11;
                blink_en = 1;
                inc = 0;
                dec = 0;
                if (set_en) begin 
                    if (btnU) begin 
                        n_state = SET_HOUR;
                        inc = 1;
                    end else if (btnD) begin 
                        n_state = SET_HOUR;
                        dec = 1;
                    end else if (btnL) begin 
                        n_state = SET_SEC;
                    end else if (btnR) begin 
                        n_state = SET_MIN;
                    end else begin 
                        n_state = SET_HOUR;
                    end
                end else begin 
                    // escape when set_en = 0
                    n_state = IDLE;
                end
            end
            
            default : begin 
                n_state = IDLE;
                watch_run = 1;
                set_active = 0;
                set_field = 3'b000;
                disp_mode = 2'b00;
                blink_en = 0;
                inc = 0;
                dec = 0;
            end
        endcase 
    end

endmodule

module w_tick_counter #(parameter TIMES = 100, BIT_WIDTH = 7, INIT_VALUE = 0)(
    input clk,
    input rst,
    input i_tick,
    input inc,
    input dec,
    output [BIT_WIDTH - 1 : 0] time_count, 
    output reg o_tick
    );

    reg [$clog2(TIMES) -1 : 0] counter_reg;
    assign time_count = counter_reg;

    always @(posedge clk, posedge rst) begin 
        if(rst) begin 
            counter_reg <= INIT_VALUE;
            o_tick <= 1'b0;
        end else begin 
            o_tick <= 1'b0;
            if (inc) begin 
                if (counter_reg == TIMES - 1)   counter_reg <= 0;
                else                            counter_reg <= counter_reg + 1;
            end else if (dec) begin 
                if (counter_reg == 0)   counter_reg <= TIMES - 1;
                else                    counter_reg <= counter_reg - 1;   
            end else if (i_tick) begin 
                if (counter_reg == TIMES - 1) begin
                    counter_reg <= 0;
                    o_tick <= 1'b1;
                end else begin 
                    counter_reg <= counter_reg + 1;
                end
            end
        end
    end

endmodule

module w_tick_gen_100hz(
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
