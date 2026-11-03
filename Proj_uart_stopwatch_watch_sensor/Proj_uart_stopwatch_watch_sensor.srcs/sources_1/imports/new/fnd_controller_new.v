`timescale 1ns / 1ps
module fnd_controller #(parameter BLINK_HALF_COUNT = 25_000_000) (
    input clk,
    input rst,
    input [1:0] display_mode,
    input [23:0] mux_out,
    input blink_en,
    input [2:0] set_field,
    input sw_disp,              // 0 : 기본 표시, 1 : 시.분 <-> 초.ms 전환
    input [1:0] wt_disp_mode,   // watch 시간 설정 중 표시 자리 (10 : 초.ms, 11 : 시.분)
    output reg [3:0] fnd_com,
    output reg [7:0] fnd_font
);
    reg [16:0] refresh_cnt;
    reg [24:0] blink_cnt;
    reg blink_on;
    reg [3:0] digit0, digit1, digit2, digit3;
    reg [3:0] selected_digit;
    reg blank_digit;
    wire [1:0] digit_sel = refresh_cnt[16:15];
    wire [4:0] hour = mux_out[23:19];
    wire [5:0] minute = mux_out[18:13];
    wire [5:0] second = mux_out[12:7];
    wire [6:0] centisec = mux_out[6:0];
    wire [15:0] distance = mux_out[15:0];
    wire [15:0] sensor_value = mux_out[15:0];

    // 1 : 시.분 표시, 0 : 초.ms 표시
    // stopwatch 기본 초.ms, watch 기본 시.분, sw_disp = 1 이면 반대로
    // watch 시간 설정 중에는 설정 자리가 보이도록 자동 전환
    wire show_hrmin = (display_mode == 2'b01) ? (wt_disp_mode[1] ? wt_disp_mode[0] : ~sw_disp)
                                              : sw_disp;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            refresh_cnt <= 0;
            blink_cnt <= 0;
            blink_on <= 1'b1;
        end else begin
            refresh_cnt <= refresh_cnt + 1'b1;
            if (!blink_en || display_mode != 2'b01) begin
                blink_cnt <= 0;
                blink_on <= 1'b1;
            end else if (blink_cnt == BLINK_HALF_COUNT - 1) begin
                blink_cnt <= 0;
                blink_on <= ~blink_on;
            end else begin
                blink_cnt <= blink_cnt + 1'b1;
            end
        end
    end

    always @(*) begin
        digit0 = 0; digit1 = 0; digit2 = 0; digit3 = 0;
        case (display_mode)
            2'b00, 2'b01: begin
                if (show_hrmin) begin
                    digit0 = minute % 10;
                    digit1 = (minute / 10) % 10;
                    digit2 = hour % 10;
                    digit3 = (hour / 10) % 10;
                end else begin
                    digit0 = centisec % 10;
                    digit1 = (centisec / 10) % 10;
                    digit2 = second % 10;
                    digit3 = (second / 10) % 10;
                end
            end
            2'b10: begin 
                digit0 = distance % 10;
                digit1 = (distance / 10) % 10;
                digit2 = (distance / 100) % 10;
                digit3 = (distance / 1000) % 10;
            end
            2'b11: begin 
                digit0 = sensor_value % 10;
                digit1 = (sensor_value / 10) % 10;
                digit2 = (sensor_value / 100) % 10;
                digit3 = (sensor_value / 1000) % 10;
            end
        endcase
    end

    always @(*) begin
        case (digit_sel)
            2'd0: begin fnd_com = 4'b1110; selected_digit = digit0; end
            2'd1: begin fnd_com = 4'b1101; selected_digit = digit1; end
            2'd2: begin fnd_com = 4'b1011; selected_digit = digit2; end
            default: begin fnd_com = 4'b0111; selected_digit = digit3; end
        endcase
        blank_digit = 1'b0;
        if (display_mode == 2'b01 && blink_en && !blink_on) begin
            case (set_field)
                3'b101: blank_digit = (digit_sel == 2'd2 || digit_sel == 2'd3); // SEC
                3'b110: blank_digit = (digit_sel == 2'd0 || digit_sel == 2'd1); // MIN
                3'b111: blank_digit = (digit_sel == 2'd2 || digit_sel == 2'd3); // HOUR
                default: blank_digit = 1'b0; 
            endcase
        end
        if (blank_digit) fnd_font = 8'hff;
        else begin
            case (selected_digit)
                4'd0: fnd_font = 8'hc0;
                4'd1: fnd_font = 8'hf9;
                4'd2: fnd_font = 8'ha4;
                4'd3: fnd_font = 8'hb0;
                4'd4: fnd_font = 8'h99;
                4'd5: fnd_font = 8'h92;
                4'd6: fnd_font = 8'h82;
                4'd7: fnd_font = 8'hf8;
                4'd8: fnd_font = 8'h80;
                4'd9: fnd_font = 8'h90;
                default: fnd_font = 8'hff;
            endcase
            if (digit_sel == 2'd2 && display_mode != 2'b10) fnd_font[7] = 1'b0;
        end
    end
endmodule
