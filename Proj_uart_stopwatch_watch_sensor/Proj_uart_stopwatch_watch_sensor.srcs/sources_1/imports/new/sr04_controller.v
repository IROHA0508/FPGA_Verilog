
`timescale 1ns / 1ps

module sr04_controller (
    input clk,
    input rst,
    input sr04_start,
    input echo,
    input us_tick,
    output reg trig,
    output reg echo_cnt_en,
    output reg echo_cnt_clear,
    output reg busy,
    output reg done,
    output reg timeout
);
    parameter TRIG_TIME    = 11;
    parameter STOP_TIME    = 10_000;
    parameter ECHO_TIMEOUT = 30_000;

    localparam TRIG_CLK_COUNT = TRIG_TIME * 100;
  
    // FSM States
    localparam IDLE     = 3'd0;
    localparam START    = 3'd1;
    localparam WAIT     = 3'd2;
    localparam DISTANCE = 3'd3;
    localparam STOP     = 3'd4;

    reg [2:0] state_reg, next_state;

    // 1us Timing Counter
    reg [15:0] time_cnt;

    // Trigger Clock Counter
    reg [15:0] trig_cnt;

    // Echo Synchronizer
    reg echo_meta, echo_sync, echo_prev;

    wire echo_rise;
    wire echo_fall;

    assign echo_rise = echo_sync & ~echo_prev;
    assign echo_fall = ~echo_sync & echo_prev;
   
    wire measure_done;
    wire measure_timeout;

    assign measure_done =
        (state_reg == DISTANCE) && echo_fall;

    assign measure_timeout =
        ((state_reg == WAIT) ||
         (state_reg == DISTANCE)) &&
         (time_cnt >= ECHO_TIMEOUT) &&
         !measure_done;
 
    // 1. Echo Synchronizer  
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            echo_meta <= 1'b0;
            echo_sync <= 1'b0;
            echo_prev <= 1'b0;
        end
        else begin
            echo_meta <= echo;
            echo_sync <= echo_meta;
            echo_prev <= echo_sync;
        end
    end

   
    // 2. State Register    
    always @(posedge clk or posedge rst) begin
        if (rst)
            state_reg <= IDLE;
        else
            state_reg <= next_state;
    end

    // 3. Trigger Clock Counter   
    always @(posedge clk or posedge rst) begin
        if (rst)
            trig_cnt <= 16'd0;
        else if (state_reg != START)
            trig_cnt <= 16'd0;
        else if (trig_cnt < TRIG_CLK_COUNT - 1)
            trig_cnt <= trig_cnt + 1'b1;
    end
  
    // 4. 1us Timing Counter   
    always @(posedge clk or posedge rst) begin
        if (rst)
            time_cnt <= 16'd0;
        else if (state_reg != next_state)
            time_cnt <= 16'd0;
        else if (us_tick)
            time_cnt <= time_cnt + 1'b1;
    end
 
    // 5. Next State Logic   
    always @(*) begin
        next_state = state_reg;

        case (state_reg)

            IDLE: begin
                if (sr04_start)
                    next_state = START;
            end

            START: begin
                if (trig_cnt >= TRIG_CLK_COUNT - 1)
                    next_state = WAIT;
            end

            WAIT: begin
                if (measure_timeout)
                    next_state = STOP;
                else if (echo_rise)
                    next_state = DISTANCE;
            end

            DISTANCE: begin
                if (measure_timeout || measure_done)
                    next_state = STOP;
            end

            STOP: begin
                if (us_tick &&
                    time_cnt >= STOP_TIME - 1)
                    next_state = IDLE;
            end

            default: begin
                next_state = IDLE;
            end

        endcase
    end
    
    // 6. Output Logic 
    always @(*) begin
        trig           = 1'b0;
        echo_cnt_en    = 1'b0;
        echo_cnt_clear = 1'b0;
        busy           = 1'b0;

        case (state_reg)

            IDLE: begin
                echo_cnt_clear = 1'b1;
            end

            START: begin
                trig = 1'b1;
                busy = 1'b1;
                echo_cnt_clear = 1'b1;
            end

            WAIT: begin
                busy = 1'b1;
                echo_cnt_clear = 1'b1;
            end

            DISTANCE: begin
                busy = 1'b1;

                echo_cnt_en = !echo_fall &&
                              !measure_timeout;
            end

            STOP: begin
                busy = 1'b0;
            end

        endcase
    end

    // 7. Done / Timeout Pulse    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            done    <= 1'b0;
            timeout <= 1'b0;
        end
        else begin
            done    <= measure_done;
            timeout <= measure_timeout;
        end
    end

endmodule
