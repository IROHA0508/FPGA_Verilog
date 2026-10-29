`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/10/08 15:08:01
// Design Name: 
// Module Name: led_fsm
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


module led_fsm(
    input clk,
    input reset,
    input sw0,
    output [1:0] led
    );
    parameter s1 = 1'b0, s2 = 1'b1;
    reg current_state, next_state;

    // state register
    always @(posedge clk, posedge reset) begin 
        if (reset) begin 
            current_state <= s1;
        end else begin
            current_state <= next_state;
        end
    end

    // next state combinational logic
    // watch input : sw, current_state
    always @(*) begin
        if (current_state == s1) begin
            if (sw0 == 1'b1) begin
                next_state = s2;
            end else begin
                next_state = current_state;
            end
        end else if (current_state == s2) begin
            if (sw0 == 1'b0) begin
                next_state = s1;
            end else begin
                next_state = current_state;
            end
        end else begin
            next_state = current_state;
        end
    end

    // output combinational logic
    // we can use always clause
    assign led = (current_state == s1) ? 2'b01 : 2'b10;
endmodule


module led_fsm_1(
    input clk,
    input reset,
    input [1:0] sw,
    output reg [2:0] led
    );
    parameter s0 = 3'b000, s1 = 3'b001, s2 = 3'b010, s3 = 3'b011, s4 = 3'b100;
    reg [3:0] c_state, n_state;

    // output combinational logic
    // assign led = (c_state == s0) ? 3'b000:
    //             (c_state == s1) ? 3'b001:
    //             (c_state == s2) ? 3'b010:
    //             (c_state == s3) ? 3'b100:
    //             (c_state == s4) ? 3'b111 : 3'b000;

    // always @(*) begin
    //     led = 3'b000;
    //     case(c_state)
    //         s0 : led = 3'b000;
    //         s1 : led = 3'b001;
    //         s2 : led = 3'b010;
    //         s3 : led = 3'b100;
    //         s4 : led = 3'b111;
    //         s0 : led = 3'b000;
    //     endcase
    // end

    // state register
    always @(posedge clk, posedge reset) begin 
        if (reset) begin 
            c_state <= s0;
        end else begin
            c_state <= n_state;
        end
    end

    // next state combinational logic
    // watch input : sw, current_state
    always @(*) begin
        n_state = c_state;
        led = 3'b000;
        case(c_state)
            s0 : begin 
                led = 3'b000;
                if (sw == 2'b01) n_state = s1;
                // else n_state = c_state;
            end 

            s1 : begin 
                led = 3'b001;
                if (sw == 2'b10) n_state = s2;
                // else n_state = c_state;
            end

            s2 : begin
                led = 3'b010;
                if (sw == 2'b11) n_state = s3;
                // else n_state = c_state;
            end

            s3 : begin
                led = 3'b100;
                if (sw == 2'b00) n_state = s0;
                else if (sw == 2'b01) n_state = s1;
                else if (sw == 2'b10) n_state = s4;
                // else n_state = c_state;
            end

            s4 : begin
                led = 3'b111;
                if (sw == 2'b00) n_state = s0;
                // else n_state = c_state;
            end

            // default is ALWAYS NEEDED
            // default: n_state = c_state;
        endcase
    end
endmodule

module fsm(
    input clk,
    input reset,
    input [1:0] sw,
    output reg clear,
    output reg run_stop
);
    parameter stop = 2'b00, run = 2'b01, s_clear = 2'b10;
    reg [1:0] c_state, n_state;

    // state register
    always @(posedge clk, posedge reset) begin 
        if (reset) begin 
            c_state <= stop;
        end else begin
            c_state <= n_state;
        end
    end

    // next state combinational logic
    // watch input : sw, current_state
    always @(*) begin
        n_state = c_state;
        run_stop = 1'b0;
        clear = 1'b0;

        case(c_state)
            stop : begin 
                run_stop = 1'b0;
                clear = 1'b0;
                if (sw[0] == 1) n_state = run;
                else if (sw[0] == 0) n_state = s_clear;
                // else n_state = c_state;
            end 

            run : begin 
                run_stop = 1'b1;
                clear = 1'b0;
                if (sw[0] == 0) n_state = stop;
                // else n_state = c_state;
            end

            s_clear : begin
                run_stop = 1'b0;
                clear = 1'b1;
                if (sw[1] == 0) n_state = stop;
                // else n_state = c_state;
            end

            // default is ALWAYS NEEDED
            // default: n_state = c_state;
        endcase
    end
endmodule