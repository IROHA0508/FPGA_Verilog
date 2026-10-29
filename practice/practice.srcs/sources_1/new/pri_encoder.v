`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/10/13 09:48:12
// Design Name: 
// Module Name: pri_encoder
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


module pri_encoder_4to2_if(
    input [3:0] enc_in,
    output reg valid,
    output reg [1:0] enc_out
    );

    always @(enc_in) begin
        valid = 1'b1;
        if      (enc_in[3]) enc_out = 2'b11;
        else if (enc_in[2]) enc_out = 2'b10;
        else if (enc_in[1]) enc_out = 2'b01;
        else if (enc_in[0]) enc_out = 2'b00;
        else begin
            valid = 1'b0;
            enc_out = 2'b00;
        end
    end

endmodule

module if_else_if(
    input selA,
    input selB,
    input selC,
    input selD,
    input [3:0] dinA,
    input [3:0] dinB,
    input [3:0] dinC,
    input [3:0] dinD,
    input [3:0] dinE,
    output reg [3:0] dout
); 
    always @(*) begin 
        if       (selA) dout = dinA;
        else if  (selB) dout = dinB;
        else if  (selC) dout = dinC;
        else if  (selD) dout = dinD;
        else     dout = dinE;
        
    end
endmodule
