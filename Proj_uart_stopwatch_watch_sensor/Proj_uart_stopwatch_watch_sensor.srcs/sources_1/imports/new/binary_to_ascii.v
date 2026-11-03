`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/10/31 14:08:43
// Design Name: 
// Module Name: binary_to_ascii
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
`timescale 1ns / 1ps

// start is accepted only while busy=0. done is a one-clock pulse.
// Uses 24 shift/add-3 iterations (double dabble), with no divider.
module bin24_to_ascii8 (
    input             clk,
    input             rst,
    input             start,
    input      [23:0] binary_data,
    output reg [63:0] ascii_data,
    output reg        busy,
    output reg        done
);
    reg [23:0] binary_reg;
    reg [31:0] bcd_reg;
    reg [4:0] bit_count;
    reg [31:0] adjusted_bcd;
    wire [31:0] shifted_bcd;
    integer i;
    integer j;

    always @(*) begin
        adjusted_bcd = bcd_reg;
        for (i = 0; i < 8; i = i + 1) begin
            if (bcd_reg[i*4 +: 4] >= 4'd5)
                adjusted_bcd[i*4 +: 4] = bcd_reg[i*4 +: 4] + 4'd3;
        end
    end

    assign shifted_bcd = {adjusted_bcd[30:0], binary_reg[23]};

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            binary_reg <= 24'd0;
            bcd_reg    <= 32'd0;
            bit_count  <= 5'd0;
            ascii_data <= "00000000";
            busy       <= 1'b0;
            done       <= 1'b0;
        end else begin
            done <= 1'b0;
            if (!busy) begin
                if (start) begin
                    binary_reg <= binary_data;
                    bcd_reg    <= 32'd0;
                    bit_count  <= 5'd0;
                    busy       <= 1'b1;
                end
            end else begin
                bcd_reg    <= shifted_bcd;
                binary_reg <= {binary_reg[22:0], 1'b0};
                if (bit_count == 5'd23) begin
                    for (j = 0; j < 8; j = j + 1)
                        ascii_data[j*8 +: 8] <=
                            8'h30 + {4'b0000, shifted_bcd[j*4 +: 4]};
                    busy <= 1'b0;
                    done <= 1'b1;
                end else begin
                    bit_count <= bit_count + 1'b1;
                end
            end
        end
    end
endmodule