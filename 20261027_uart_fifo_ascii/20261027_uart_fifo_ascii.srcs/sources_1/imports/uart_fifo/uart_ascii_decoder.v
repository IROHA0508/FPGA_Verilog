`timescale 1ns / 1ps

module ascii_decoder (
    input            clk,
    input            rst,
    input            enable,     // RX FIFO에 데이터가 있음 (= ~empty)
    input      [7:0] ascii,      // RX FIFO의 popdata
    output reg [3:0] binary,

    // uart fifo ascii
    output reg pop,
    output     run_stop,
    output     clear,
    output     mode,
    output     status
);

    reg [7:0] data_reg, data_next;
    reg run_stop_reg, run_stop_next;
    reg clear_reg,    clear_next;
    reg mode_reg,     mode_next;
    reg status_reg,   status_next;

    assign run_stop = run_stop_reg;
    assign clear    = clear_reg;
    assign mode     = mode_reg;
    assign status   = status_reg;

    // SL: 레지스터 갱신만 담당
    always @(posedge clk, posedge rst) begin
        if (rst) begin
            data_reg     <= 8'h00;
            run_stop_reg <= 1'b0;
            clear_reg    <= 1'b0;
            mode_reg     <= 1'b0;
            status_reg   <= 1'b0;
        end else begin
            data_reg     <= data_next;
            run_stop_reg <= run_stop_next;
            clear_reg    <= clear_next;
            mode_reg     <= mode_next;
            status_reg   <= status_next;
        end
    end

    // CL: next 값 계산
    always @(*) begin
        binary    = 4'h0;
        pop       = 1'b0;
        data_next = data_reg;

        run_stop_next = 1'b0;
        clear_next    = 1'b0;
        mode_next     = 1'b0;
        status_next   = 1'b0;

        if (enable) begin
            data_next = ascii;
            pop       = 1'b1;

            case (ascii)
                8'h52, 8'h72: run_stop_next = 1'b1;  // R, r
                8'h43, 8'h63: clear_next    = 1'b1;  // C, c
                8'h55, 8'h75: mode_next     = 1'b1;  // U, u
                8'h53, 8'h73: status_next   = 1'b1;  // S, s
            endcase
        end else begin
            case (data_reg)
                8'h30:        binary = 4'h0;
                8'h31:        binary = 4'h1;
                8'h32:        binary = 4'h2;
                8'h33:        binary = 4'h3;
                8'h34:        binary = 4'h4;
                8'h35:        binary = 4'h5;
                8'h36:        binary = 4'h6;
                8'h37:        binary = 4'h7;
                8'h38:        binary = 4'h8;
                8'h39:        binary = 4'h9;
                8'h41, 8'h61: binary = 4'ha;  // A
                8'h42, 8'h62: binary = 4'hb;  // B
                8'h44, 8'h64: binary = 4'hd;  // D
                8'h45, 8'h65: binary = 4'he;  // E
                8'h46, 8'h66: binary = 4'hf;  // F
            endcase
        end
    end
endmodule
