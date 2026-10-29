`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/10/13 08:54:12
// Design Name: 
// Module Name: pattern_detect_moore
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


module pattern_detect_moore(
    input clk,
    input reset,
    input din_bit,
    output reg ptn_check
    );

    parameter S0 = 3'b000, S1 = 3'b001, S2 = 3'b010, S3 = 3'b011, S4 = 3'b100;
    reg [2:0] c_state, n_state;

    // State Register
    always @(posedge clk, posedge reset) begin 
        if (reset)  c_state <= S0;
        else        c_state <= n_state;
    end

    // next state combinational logic
    always @(*) begin
        n_state = c_state;
        ptn_check = 0;

        case(c_state)
            S0 : begin 
                ptn_check = 0;
                if (din_bit == 1)   n_state = S0;
                else                n_state = S1;
            end 

            S1 : begin 
                ptn_check = 0;
                if (din_bit == 1)   n_state = S2;
                else                n_state = S1;
            end 

            S2 : begin 
                ptn_check = 0;
                if (din_bit == 1)   n_state = S0;
                else                n_state = S3;
            end 

            S3 : begin 
                ptn_check = 0;
                if (din_bit == 1)   n_state = S4;
                else                n_state = S1;
            end 

            S4 : begin 
                ptn_check = 1;
                if (din_bit == 1)   n_state = S0;
                else                n_state = S1;
            end 

            // end
            // default is ALWAYS NEEDED
            default: n_state = S0;
        endcase
    end
endmodule
