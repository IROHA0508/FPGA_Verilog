`timescale 1ns / 1ps

module uart_ascii_decoder(
    input clk, rst,
    input rx, 
    output tx,
    // fnd
    output [3:0] fnd_com,
    output [7:0] fnd_font
    );

    wire w_rx_done;
    wire [7:0] w_rx_data;
    wire [3:0] w_bin;

    uart_loopback U_UART_LOOPBACK(
        .clk(clk),
        .rst(rst),
        .rx(rx),    // from PC
        .tx(tx),     // to PC
        .rx_done(w_rx_done),
        .rx_data(w_rx_data)
    );

    ascii_decoder U_ASCII_DECODER(
        .clk(clk),
        .rst(rst),
        .enable(w_rx_done),
        .ascii(w_rx_data),
        .binary(w_bin)
    );

    fnd_controller U_FND_CNTL(
        .clk(clk),
        .reset(rst),
        .fnd_data(w_bin),  // 9-bit {c, s}, c값이 256을 넘어가는 수이므로 MSB에 위치
        .fnd_com(fnd_com),
        .fnd_font(fnd_font)
    );

endmodule

module ascii_decoder(
    input clk, rst,
    input enable,
    input [7:0] ascii,
    output reg [3:0] binary
    );

    reg [7:0] data_reg, data_next;

    always @(posedge clk, posedge rst) begin 
        if(rst) begin 
            data_reg <= 0;
        end else begin 
            data_reg <= data_next;
        end
    end

    always @(*) begin 
        binary = 4'h0;
        data_next = data_reg;

        if (enable) begin
            data_next = ascii;
        end else begin
            case(data_reg)
                8'h30 : binary = 4'h0;
                8'h31 : binary = 4'h1;
                8'h32 : binary = 4'h2;
                8'h33 : binary = 4'h3;
                8'h34 : binary = 4'h4;
                8'h35 : binary = 4'h5;
                8'h36 : binary = 4'h6;
                8'h37 : binary = 4'h7;
                8'h38 : binary = 4'h8;
                8'h39 : binary = 4'h9;
                8'h41, 8'h61 : binary = 4'ha;     // A
                8'h42, 8'h62 : binary = 4'hb;     // B
                8'h43, 8'h63 : binary = 4'hc;     // C
                8'h44, 8'h64 : binary = 4'hd;     // D
                8'h45, 8'h65 : binary = 4'he;     // E
                8'h46, 8'h66 : binary = 4'hf;     // F
            endcase
        end
    end
endmodule