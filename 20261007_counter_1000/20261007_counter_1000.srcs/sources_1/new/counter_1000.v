`timescale 1ns / 1ps

// Using Switch
module counter_10000(
    input clk,
    input reset,
    // input [2:0] sw,
    input btnU, //mode
    input btnL, //clear
    input btnR, // run_stop
    output [3:0] fnd_com,
    output [7:0] fnd_font
    );

    wire [13:0] w_counter;
    wire w_run_stop, w_clear, w_mode;
    wire w_btn_run_stop, w_btn_clear, w_btn_mode;

    btn_debounce U_BD_RUNSTOP(
        .clk(clk),
        .reset(reset),
        .i_btn(btnR),
        .o_btn(w_btn_run_stop)
    );

    btn_debounce U_BD_CLEAR(
        .clk(clk),
        .reset(reset),
        .i_btn(btnL),
        .o_btn(w_btn_clear)
    );

    btn_debounce U_BD_MODE(
        .clk(clk),
        .reset(reset),
        .i_btn(btnU),
        .o_btn(w_btn_mode)
    );

    control_btn_unit U_CONTROL_UNIT(
        .clk(clk),
        .reset(reset),
        // .sw(sw),
        .btn_run_stop(w_btn_run_stop),
        .btn_clear(w_btn_clear),
        .btn_mode(w_btn_mode),
        .run_stop(w_run_stop),
        .clear(w_clear),
        .mode(w_mode)
    );

    counter_datapath U_COUNTER_DATAPATH(
        .clk(clk),
        .reset(reset),
        // .sw(sw),
        .run_stop(w_run_stop),
        .clear(w_clear),
        .mode(w_mode),
        .counter(w_counter)
    );

    fnd_controller U_FND_CNTL(
        .clk(clk),
        .reset(reset),
        .fnd_data(w_counter),
        .fnd_com(fnd_com),
        .fnd_font(fnd_font)
    );
    
endmodule

module counter_datapath(
    input clk,
    input reset,
    // Additional Implementation
    // sw[0] 0: Stop, 1 : Run
    // sw[1] reset when used
    // sw[2] 0 : Count-Up, 1 : Count-Down 
    // input [2:0] sw,
    input run_stop,
    input clear,
    input mode,
    output [13:0] counter
);

    wire w_tick;

    tick_gen U_TICK_GEN(
        .clk(clk),
        .reset(reset),
        .run_stop(run_stop),
        .clear(clear),
        .o_tick(w_tick)
    );

    tick_counter U_TICK_COUNTER (
        .clk(clk),
        .reset(reset),
        .i_tick(w_tick),
        .clear(clear),
        .mode(mode),
        .counter(counter)
    );
endmodule

// to make 10Hz tick gen
module tick_gen(
    input clk,
    input reset,
    input run_stop,
    input clear,
    output o_tick
);
    parameter F_COUNT = 10_000_000;
    reg [$clog2(F_COUNT)-1:0] counter_reg;
    reg tick_reg;

    assign o_tick = tick_reg;

    always @(posedge clk, posedge reset) begin
        // when reset signal, initialize counter_reg, o_tick
        if (reset | clear) begin
            counter_reg <= 0;
            tick_reg <= 1'b0;
        end else begin
            if (run_stop) begin
                counter_reg <= counter_reg + 1;
                // when counter_reg is F_COUNT -1, make 10Hz tick signal
                if (counter_reg == F_COUNT-1) begin
                    counter_reg <= 0;

                    // reverse tick_reg
                    tick_reg <= 1'b1;
                end else begin
                    // else, keep tick_reg signal
                    tick_reg <= 1'b0;
                end
            end
        end
    end
endmodule

module tick_counter(
    input clk,
    input reset,
    input i_tick,
    // input [2:0] sw,
    // 0 ~ 10000 needs 14 bits
    input clear,
    input mode,
    output [13:0]counter
);
    reg [13:0] counter_reg;
    
    assign counter = counter_reg;
    // Count Down Simulation
    // assign counter = 9900;

    always @(posedge clk, posedge reset) begin
        if (reset | clear) begin 
            counter_reg <= 0;
        end else  begin 
            if (!mode) begin
                // when input tick is 1, increase counter_reg
                if (i_tick) begin
                    counter_reg <= counter_reg + 1;
                    if (counter_reg == 10000-1) begin
                        counter_reg <= 0;
                    end
                end 
            end else begin 
                if (i_tick) begin
                    counter_reg <= counter_reg - 1;
                    if (counter_reg == 0) begin
                        counter_reg <= 9999;
                    end
                end 
            end 
        end
    end
endmodule