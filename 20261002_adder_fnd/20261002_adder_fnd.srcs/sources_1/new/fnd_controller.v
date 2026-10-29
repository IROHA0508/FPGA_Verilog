`timescale 1ns / 1ps

module fnd_controller (
    input clk,
    input reset,
    input  [8:0] fnd_data,  // 9-bit {c, s}, c값이 256을 넘어가는 수이므로 MSB에 위치
    output [3:0] fnd_com,
    output [7:0] fnd_font
);

    wire [3:0] w_ds1, w_ds10, w_ds100, w_ds1000, w_mux_out;

    // ds_sel wire 연결용 선언
    wire [1:0] w_ds_sel;

    // clock wire 연결용
    wire w_clk_800hz;

    clk_div_800hz U_CLK_DIV_800HZ(
        .clk(clk),
        .reset(reset),
        .o_clk_800hz(w_clk_800hz)
    );
    
    counter_4 U_COUNTER_4 (
        .clk(w_clk_800hz),
        .reset(reset),
        .ds_sel(w_ds_sel)
    );

    decoder_2x4 U_DECODER_2x4 (
        .ds_sel (w_ds_sel),  // ds_sel → w_ds_sel
        .fnd_com(fnd_com)
    );

    digit_splitter U_DIGIT_SPLITTER (
        .dsin  (fnd_data),  // 받은 9-bit {c, s} 데이터
        .ds1   (w_ds1),
        .ds10  (w_ds10),
        .ds100 (w_ds100),
        .ds1000(w_ds1000)
    );

    mux_4x1 U_MUX_4x1 (
        .sel(w_ds_sel),     // ds_sel → w_ds_sel
        .in0(w_ds1),
        .in1(w_ds10),
        .in2(w_ds100),
        .in3(w_ds1000),
        .mux_out(w_mux_out)
    );

    bcd U_BCD (
        .bin     (w_mux_out),
        .fnd_font(fnd_font)
    );

endmodule

module clk_div_800hz(
    input clk,
    input reset,
    output reg o_clk_800hz
);

    //reg [15:0] counter_reg;
    reg [$clog2(62500)-1:0] counter_reg;

    // 상승 엣지 posedge: 0 → 1 상승 경계부분 (rising)
    // 하강 엣지 negedge: 1 → 0 하락 경계부분 (falling)
    // * 반 clock이 필요한 경우 제외하고 모두 상승 edge 기준으로 설계할 것.
    always @(posedge clk) begin
        // reset 상태, reset == 1'b1과 등가
        if (reset) begin
            counter_reg <= 16'd0;
            o_clk_800hz <= 1'b0;
        end
        else begin
            counter_reg <= counter_reg + 1;
            if (counter_reg == (62_500 - 1)) begin  // synthesis에 '_' 영향 X
                counter_reg <= 16'd0;           // count 0 초기화
                o_clk_800hz <= ~o_clk_800hz;    // clock 반전
            end
        end
    end

endmodule


module counter_4 (
    input clk,
    input reset,
    output [1:0] ds_sel
);

    // 출력 유지 위해 reg 자료형 사용 (wire 유지 안 됨, 연결용)
    reg [1:0] counter_reg;

    assign ds_sel = counter_reg;

    // 1. reset → 상승 edge (1이면) → counter 초기화
    // 2. clock의 상승 edge가 올 때마다 counter 1씩 증가
    always @(posedge clk, posedge reset) begin  // 반대의 경우 negedge
        // reset == 1'b1과 등가
        if (reset) begin
            counter_reg <= 2'b00;    // '00'을 counter_reg로 출력 할당, '<=' 의미: ??
            // Operation 진행 (상승 edge & !reset)
        end else begin
            counter_reg <= counter_reg + 1;
        end

    end

endmodule

module decoder_2x4 (
    input [1:0] ds_sel,
    output reg [3:0] fnd_com
);
    always @(ds_sel) begin
        case (ds_sel)
            2'b00: fnd_com = 4'b1110;
            2'b01: fnd_com = 4'b1101;
            2'b10: fnd_com = 4'b1011;
            2'b11: fnd_com = 4'b0111;
        endcase
    end

endmodule

// muxer는 항상 selection bit 필요
module mux_4x1 (
    input [1:0] sel,
    input [3:0] in0,
    input [3:0] in1,
    input [3:0] in2,
    input [3:0] in3,
    output reg [3:0] mux_out
);

    // 합성기에 따라 예외처리될 수 있으므로 sel만 넣지말고 다른 input들도 넣어준다.
    always @(*) begin  // 'always @ (sel, in0, in1, in2, in3) begin'과 동일
        // case 조건문을 통해 Muxer의 동작 기술
        case (sel)
            2'b00: mux_out = in0;
            2'b01: mux_out = in1;
            2'b10: mux_out = in2;
            2'b11: mux_out = in3;
            default:
            mux_out = in0;  // full case여서 default 안 넣어도 됨
        endcase
    end

endmodule

module bcd (
    input [3:0] bin,
    output reg [7:0] fnd_font
);

    // 똑똑하면 assign문 써도 됨
    always @(bin) begin
        case (bin)  // 감시 대상 bin
            4'b0000: fnd_font = 8'hc0;
            4'b0001: fnd_font = 8'hf9;
            4'b0010: fnd_font = 8'ha4;
            4'b0011: fnd_font = 8'hb0;
            4'b0100: fnd_font = 8'h99;
            4'b0101: fnd_font = 8'h92;
            4'b0110: fnd_font = 8'h82;
            4'b0111: fnd_font = 8'hf8;
            4'b1000: fnd_font = 8'h80;
            4'b1001: fnd_font = 8'h90;
            4'b1010: fnd_font = 8'h88;
            4'b1011: fnd_font = 8'h83;
            4'b1100: fnd_font = 8'hc6;
            4'b1101: fnd_font = 8'ha1;
            4'b1110: fnd_font = 8'h86;
            4'b1111: fnd_font = 8'h8e;
            default: fnd_font = 8'hff;
        endcase
    end

endmodule

module digit_splitter (
    input  [8:0] dsin,
    output [3:0] ds1,    // digit 1
    output [3:0] ds10,   // digit 10
    output [3:0] ds100,  // digit 100
    output [3:0] ds1000  // digit 1000
);

    // Modulo 연산자 %
    // 510
    assign ds1 = dsin % 10;  // 0
    assign ds10 = (dsin / 10) % 10;  // 51 % 10 = 1
    assign ds100 = (dsin / 100) % 10;  // 5 % 10 = 5
    assign ds1000 = dsin / 1000;

endmodule