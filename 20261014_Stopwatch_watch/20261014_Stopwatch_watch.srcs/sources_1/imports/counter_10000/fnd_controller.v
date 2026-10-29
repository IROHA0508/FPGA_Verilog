`timescale 1ns / 1ps

module fnd_controller #(
    parameter MSEC_BIT_WIDTH = 7,
    parameter SEC_BIT_WIDTH = 6,
    parameter MIN_BIT_WIDTH = 6,
    parameter HOUR_BIT_WIDTH = 5,
    parameter TIME_WIDTH = MSEC_BIT_WIDTH + SEC_BIT_WIDTH + MIN_BIT_WIDTH + HOUR_BIT_WIDTH
)   (
    input clk,
    input rst,
    input sw_stopwatch_mode,
    input sw_display_mode,
    input [1:0] disp_mode,
    input [2:0] set_field,
    input blink_en,
    input [TIME_WIDTH-1:0] wt_time,
    input [TIME_WIDTH-1:0] sw_time,
    output [3:0] fnd_com,
    output [7:0] fnd_font,
    output led_hrmin,
    output led_watch
);

    wire [3:0] w_msec_ds1, w_msec_ds10;
    wire [3:0] w_sec_ds1, w_sec_ds10;
    wire [3:0] w_min_ds1, w_min_ds10;
    wire [3:0] w_hour_ds1, w_hour_ds10;
    wire [3:0] w_mux_out, w_msec_sec_mux_out, w_min_hour_mux_out;
    wire w_dot_onoff;

    // ds_sel wire 연결용 선언
    wire [2:0] w_ds_sel;

    // clock wire 연결용
    wire w_clk_800hz;

    wire w_blink_on;
    wire w_off        = blink_en & ~w_blink_on;          // 소등 구간
    wire w_hide_msec  = w_off & (set_field == 3'b100);
    wire w_hide_sec   = w_off & (set_field == 3'b101);
    wire w_hide_min   = w_off & (set_field == 3'b110);
    wire w_hide_hour  = w_off & (set_field == 3'b111);
    wire w_sel_display = disp_mode[1] ? disp_mode[0] : sw_display_mode;
    assign led_hrmin = w_sel_display;
    assign led_watch = ~sw_stopwatch_mode;
    wire w_dot = blink_en ? 1'b0 : w_dot_onoff;          // SET 중에는 dot 항상 켜짐

    wire [TIME_WIDTH-1:0] w_time = sw_stopwatch_mode ? sw_time : wt_time;

    wire [MSEC_BIT_WIDTH-1:0] msec = w_time[0 +: MSEC_BIT_WIDTH];
    wire [SEC_BIT_WIDTH-1:0]  sec  = w_time[MSEC_BIT_WIDTH +: SEC_BIT_WIDTH];
    wire [MIN_BIT_WIDTH-1:0]  min  = w_time[(MSEC_BIT_WIDTH+SEC_BIT_WIDTH) +: MIN_BIT_WIDTH];
    wire [HOUR_BIT_WIDTH-1:0] hour = w_time[(MSEC_BIT_WIDTH+SEC_BIT_WIDTH+MIN_BIT_WIDTH) +: HOUR_BIT_WIDTH];

    blink_gen U_BLINK(
        .clk(clk), 
        .rst(rst),
        .blink_en(blink_en),
        .blink_on(w_blink_on)
    );

    clk_div_800hz U_CLK_DIV_800HZ(
        .clk(clk),
        .reset(rst),
        .o_clk_800hz(w_clk_800hz)
    );
    
    counter_8 U_COUNTER_8 (
        .clk(w_clk_800hz),
        .reset(rst),
        .ds_sel(w_ds_sel)
    );

    decoder_2x4 U_DECODER_2x4 (
        .ds_sel (w_ds_sel[1:0]),  // ds_sel → w_ds_sel
        .fnd_com(fnd_com)
    );

    digit_splitter #(.BIT_WIDTH(MSEC_BIT_WIDTH)) U_MSEC_DIGIT_SPLITTER (
        .dsin  (msec),  // 받은 9-bit {c, s} 데이터
        .ds1   (w_msec_ds1),
        .ds10  (w_msec_ds10)
    );

    digit_splitter #(.BIT_WIDTH(SEC_BIT_WIDTH)) U_SEC_DIGIT_SPLITTER (
        .dsin  (sec),  // 받은 9-bit {c, s} 데이터
        .ds1   (w_sec_ds1),
        .ds10  (w_sec_ds10)
    );
    
    digit_splitter #(.BIT_WIDTH(MIN_BIT_WIDTH)) U_MIN_DIGIT_SPLITTER (
        .dsin  (min),  // 받은 9-bit {c, s} 데이터
        .ds1   (w_min_ds1),
        .ds10  (w_min_ds10)
    );
    
    digit_splitter #(.BIT_WIDTH(HOUR_BIT_WIDTH)) U_HOUR_DIGIT_SPLITTER (
        .dsin  (hour),  // 받은 9-bit {c, s} 데이터
        .ds1   (w_hour_ds1),
        .ds10  (w_hour_ds10)
    );

    dot_comparator U_DOT_COMP(
        .msec(msec),
        .dot_onoff(w_dot_onoff)
    );

    mux_8x1 U_MSEC_SEC_MUX_8x1 (
        .sel(w_ds_sel),     // ds_sel → w_ds_sel
        .in0(w_hide_msec ? 4'hf : w_msec_ds1),
        .in1(w_hide_msec ? 4'hf : w_msec_ds10),
        .in2(w_hide_sec ? 4'hf: w_sec_ds1),
        .in3(w_hide_sec ? 4'hf : w_sec_ds10),
        .in4(4'hf),
        .in5(4'hf),
        .in6({3'b111, w_dot}), // dot display
        .in7(4'hf),
        .mux_out(w_msec_sec_mux_out)
    );

    mux_8x1 U_MIN_HOUR_MUX_8x1 (
        .sel(w_ds_sel),     // ds_sel → w_ds_sel
        .in0(w_hide_min ? 4'hf: w_min_ds1),
        .in1(w_hide_min ? 4'hf: w_min_ds10),
        .in2(w_hide_hour ? 4'hf: w_hour_ds1),
        .in3(w_hide_hour ? 4'hf: w_hour_ds10),
        .in4(4'hf),
        .in5(4'hf),
        .in6({3'b111, w_dot}), // dot display
        .in7(4'hf),
        .mux_out(w_min_hour_mux_out)
    );

    mux_2x1 U_MUX_DISPLAY_MODE(
        .sel(w_sel_display),
        .in0(w_msec_sec_mux_out),
        .in1(w_min_hour_mux_out),
        .mux_out(w_mux_out)
    );

    bcd U_BCD (
        .bin     (w_mux_out),
        .fnd_font(fnd_font)
    );
endmodule

module blink_gen #(parameter HALF_COUNT = 25_000_000)(   // 100MHz 기준 0.25s마다 반전
    input  clk, rst, blink_en,
    output reg blink_on
);
    reg [$clog2(HALF_COUNT)-1:0] counter_reg;
    always @(posedge clk, posedge rst) begin
        if (rst | ~blink_en) begin           // SET이 아니면 항상 켜짐, SET 진입 시 켜진 상태에서 시작
            counter_reg <= 0;
            blink_on    <= 1'b1;
        end else if (counter_reg == HALF_COUNT - 1) begin
            counter_reg <= 0;
            blink_on    <= ~blink_on;
        end else begin
            counter_reg <= counter_reg + 1;
        end
    end
endmodule

module dot_comparator(
    input [6:0] msec,
    output dot_onoff
    );
    // 1 if bigger than 50, 0 otherwise
    assign dot_onoff = (msec >= 50) ? 1 : 0;
endmodule

module  mux_2x1(
    input sel,
    input [3:0] in0,
    input [3:0] in1,
    output [3:0] mux_out
); 
    assign mux_out = (sel) ? in1 : in0;
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


module counter_8 (
    input clk,
    input reset,
    output [2:0] ds_sel
);

    // 출력 유지 위해 reg 자료형 사용 (wire 유지 안 됨, 연결용)
    reg [2:0] counter_reg;

    assign ds_sel = counter_reg;

    // 1. reset → 상승 edge (1이면) → counter 초기화
    // 2. clock의 상승 edge가 올 때마다 counter 1씩 증가
    always @(posedge clk, posedge reset) begin  // 반대의 경우 negedge
        // reset == 1'b1과 등가
        if (reset) begin
            counter_reg <= 3'b000;    // '00'을 counter_reg로 출력 할당, '<=' 의미: ??
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
module mux_8x1 (
    input [2:0] sel,
    input [3:0] in0,
    input [3:0] in1,
    input [3:0] in2,
    input [3:0] in3,
    input [3:0] in4,
    input [3:0] in5,
    input [3:0] in6,
    input [3:0] in7,
    output reg [3:0] mux_out
);

    // 합성기에 따라 예외처리될 수 있으므로 sel만 넣지말고 다른 input들도 넣어준다.
    always @(*) begin  // 'always @ (sel, in0, in1, in2, in3) begin'과 동일
        // case 조건문을 통해 Muxer의 동작 기술
        case (sel)
            3'b000: mux_out = in0;
            3'b001: mux_out = in1;
            3'b010: mux_out = in2;
            3'b011: mux_out = in3;
            3'b100: mux_out = in4;
            3'b101: mux_out = in5;
            3'b110: mux_out = in6;
            3'b111: mux_out = in7;
            default: mux_out = in0;  // full case여서 default 안 넣어도 됨
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
            // dot only display
            4'b1110: fnd_font = 8'h7f;
            // all off
            4'b1111: fnd_font = 8'hff;
            default: fnd_font = 8'hff;
        endcase
    end

endmodule

module digit_splitter #(parameter BIT_WIDTH = 7)(
    input  [BIT_WIDTH - 1:0] dsin,
    output [3:0] ds1,    // digit 1
    output [3:0] ds10   // digit 10
);
    // Modulo 연산자 %
    // 510
    assign ds1 = dsin % 10;  // 0
    assign ds10 = (dsin / 10) % 10;  // 51 % 10 = 1
endmodule