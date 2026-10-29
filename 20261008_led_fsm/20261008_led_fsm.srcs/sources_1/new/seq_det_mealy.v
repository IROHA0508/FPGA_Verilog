`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/10/12 12:27:45
// Design Name: 
// Module Name: seq_det_mealy
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


module seq_det_mealy(
    input clk,
    input reset,
    input din_bit,
    output dout_bit
    );

    reg [2:0] state_reg, next_state;

    parameter start = 3'b000, rd0_once = 3'b001, rd1_once = 3'b010, rd0_twice = 3'b011, rd1_twice = 3'b100;

    always @(state_reg or din_bit) begin 
        case(state_reg)
            start:  if      (din_bit == 0)   next_state = rd0_once;
                    else if (din_bit == 1)   next_state = rd1_once;
                    else                     next_state = start;

            rd0_once:   if      (din_bit == 0)   next_state = rd0_twice;
                        else if (din_bit == 1)   next_state = rd1_once;
                        else                     next_state = start;

            rd0_twice:  if      (din_bit == 0)   next_state = rd0_twice;
                        else if (din_bit == 1)   next_state = rd1_once;
                        else                     next_state = start;

            rd1_once:   if      (din_bit == 0)   next_state = rd0_once;
                        else if (din_bit == 1)   next_state = rd1_twice;
                        else                     next_state = start;

            rd1_twice:  if      (din_bit == 0)   next_state = rd0_once;
                        else if (din_bit == 1)   next_state = rd1_twice;
                        else                     next_state = start;
            default:                             next_state = start;
        endcase
    end

    always @(posedge clk or posedge reset) begin 
        if (reset == 1) state_reg <= start;
        else            state_reg <= next_state;
    end

    // Mealy
    // assign dout_bit = (((state_reg == rd0_twice) && (din_bit == 0)) || ((state_reg == rd1_twice) && (din_bit == 1))) ? 1 : 0;

    // Moore
    assign dout_bit = ((state_reg == rd0_twice) || (state_reg == rd1_twice)) ? 1 : 0;
endmodule
