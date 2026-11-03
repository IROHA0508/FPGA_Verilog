`timescale 1ns / 1ps

module control_btn_unit(
    input clk,
    input reset,
    input btn_run_stop, // run_stop
    input btn_clear, // clear
    input btn_mode,
    // input sw,   // mode
    output reg run_stop,
    output reg clear,
    output mode
);

    parameter STOP = 2'b00, RUN = 2'b01, CLEAR = 2'b10, MODE = 2'b11;
    reg [1:0] c_state, n_state;

    // mode_reg means current mode, mode_next means next mode
    reg mode_reg, mode_next;
    assign mode = mode_reg;

    // state register
    always @(posedge clk, posedge reset) begin 
        if (reset)  begin 
            c_state <= STOP;    
            mode_reg <= 0;
        end
        else begin
            c_state <= n_state; 
            mode_reg <= mode_next;
        end
    end

    // next state combinational logic
    // watch input : sw, current_state
    always @(*) begin
        n_state = c_state;
        run_stop = 1'b0;
        clear = 1'b0;
        mode_next = mode_reg;

        case(c_state)
            STOP : begin 
                run_stop = 1'b0;
                clear = 1'b0;
                if (btn_run_stop == 1) n_state = RUN;
                else if (btn_clear == 1) n_state = CLEAR;
                else if (btn_mode == 1) n_state  = MODE;
                // else n_state = c_state;
            end 

            RUN : begin 
                run_stop = 1'b1;
                // clear = 1'b0;
                if (btn_run_stop == 1) n_state = STOP;
                // else n_state = c_state;
            end

            CLEAR : begin
                // run_stop = 1'b0;
                clear = 1'b1;
                n_state = STOP;     // next posedge clk
                // else n_state = c_state;
            end

            MODE : begin
                mode_next = ~mode_reg;
                n_state = STOP;
            end

            // default is ALWAYS NEEDED
            // default: n_state = c_state;
        endcase
    end
endmodule