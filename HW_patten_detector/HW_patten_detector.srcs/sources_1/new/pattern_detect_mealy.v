`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/10/13 08:54:12
// Design Name: 
// Module Name: pattern_detect_mealy
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


module pattern_detect_mealy(
    input clk,
    input reset,
    input din_bit,
    output ptn_check
    );

    parameter S0 = 2'b00, S1 = 2'b01, S2 = 2'b10, S3 = 2'b11;
    reg [1:0] c_state, n_state;

    // State Register
    always @(posedge clk, posedge reset) begin 
        if (reset)  c_state <= S0;
        else        c_state <= n_state;
    end

    // next state combinational logic
    always @(*) begin
        n_state = c_state;

        case(c_state)
            S0 : begin 
                // ptn_check = 0;
                if (din_bit == 1)   n_state = S0;
                else                n_state = S1;
            end 

            S1 : begin 
                // ptn_check = 0;
                if (din_bit == 1)   n_state = S2;
                else                n_state = S1;
            end 

            S2 : begin 
                // ptn_check = 0;
                if (din_bit == 1)   n_state = S0;
                else                n_state = S3;
            end 

            S3 : begin 
                // ptn_check = 0;
                if (din_bit == 1)   n_state = S0;
                else                n_state = S1;
            end 

            // end
            // default is ALWAYS NEEDED
            default: n_state = S0;
        endcase
    end

    // Output Combinational Logic
    assign ptn_check = (c_state == S3) && (din_bit == 1);
endmodule
