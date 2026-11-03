`timescale 1ns / 1ps


module project_top (
    input        clk,
    input        rst,       // btnC
    input  [3:0] sw,        // [1:0] 모드, [2] watch 시간 설정, [3] 0 : 온도, 1 : 습도
    input        sw_disp,   // sw[15], 0 : 기본 표시, 1 : 시.분 <-> 초.ms 전환
    input        btnR,      // run,stop or move right
    input        btnL,      // clear or move_left
    input        btnU,      // up,down or watch_up
    input        btnD,      // Laptime or watch_down
    input        rx,        // from PC
    output       tx,        // to PC
    input        echo,      // sr04
    output       trig,      // sr04
    inout        dht11_io,  // dht11 single wire
    output [3:0] fnd_com,
    output [7:0] fnd_font,
    output [1:0] led        // 현재 모드 표시
);
    wire w_btnR, w_btnL, w_btnU, w_btnD;
    wire w_uart_R, w_uart_L, w_uart_U, w_uart_D;
    wire w_uart_0, w_uart_1, w_uart_2, w_uart_3;
    wire [3:0] w_sw_btn, w_wt_btn;
    wire w_sr04_start, w_dht11_start, w_sender_start;
    wire w_sender_ready, w_result_valid;
    wire w_sw_dth, w_us_tick;
    wire [1:0] w_displaymode;
    wire [23:0] w_sw_time, w_wt_time;
    wire [2:0] w_set_field;
    wire [1:0] w_wt_disp_mode;  // watch 시간 설정 중 표시 자리 (10 : 초.ms, 11 : 시.분)
    wire w_blink_en;
    wire w_sr04_done, w_sr04_timeout;
    wire [15:0] w_distance;
    wire w_dht11_done, w_dht11_valid;
    wire [39:0] w_dht11_data;
    reg [23:0] fnd_data;
    reg [39:0] result_data;

    assign led = w_displaymode;

    btn_debounce U_BTN_R (
        .clk  (clk),
        .reset(rst),
        .i_btn(btnR),
        .o_btn(w_btnR)
    );

    btn_debounce U_BTN_L (
        .clk  (clk),
        .reset(rst),
        .i_btn(btnL),
        .o_btn(w_btnL)
    );

    btn_debounce U_BTN_U (
        .clk  (clk),
        .reset(rst),
        .i_btn(btnU),
        .o_btn(w_btnU)
    );

    btn_debounce U_BTN_D (
        .clk  (clk),
        .reset(rst),
        .i_btn(btnD),
        .o_btn(w_btnD)
    );

    UART_FIFO_ASCII U_UART (
        .clk         (clk),
        .rst         (rst),
        .rx          (rx),
        .tx          (tx),
        .uart_R      (w_uart_R),
        .uart_L      (w_uart_L),
        .uart_U      (w_uart_U),
        .uart_D      (w_uart_D),
        .stopwatch   (w_uart_0),        // '0'
        .watch       (w_uart_1),        // '1'
        .sr04_start  (w_uart_2),        // '2', 센서가 아니라 CU로 전달
        .dht11_start (w_uart_3),        // '3', 센서가 아니라 CU로 전달
        .result_done (w_sender_start),
        .result_valid(w_result_valid),
        .result_type (w_displaymode),
        .result_data (result_data),
        .sender_ready(w_sender_ready),
        .sender_busy ()
    );

    top_control_unit U_TOP_CNTL_UNIT (
        .clk         (clk),
        .rst         (rst),
        .sw          (sw[1:0]),         // 모드 전이 스위치
        .sw_dth      (sw[3]),           // 온도, 습도 전환 스위치
        .btnR        (w_btnR),
        .btnL        (w_btnL),
        .btnU        (w_btnU),
        .btnD        (w_btnD),
        .uart_R      (w_uart_R),
        .uart_L      (w_uart_L),
        .uart_U      (w_uart_U),
        .uart_D      (w_uart_D),
        .uart_0      (w_uart_0),
        .uart_1      (w_uart_1),
        .uart_2      (w_uart_2),
        .uart_3      (w_uart_3),
        .sr04_done   (w_sr04_done),
        .sr04_timeout(w_sr04_timeout),
        .dht11_done  (w_dht11_done),
        .dht11_valid (w_dht11_valid),
        .sender_ready(w_sender_ready),
        .o_sw_btn    (w_sw_btn),        // {lap, mode, clear, run_stop}
        .o_wt_btn    (w_wt_btn),        // {D, U, L, R}
        .sr04_start  (w_sr04_start),
        .dht11_start (w_dht11_start),
        .sender_start(w_sender_start),
        .result_valid(w_result_valid),
        .o_sw_dth    (w_sw_dth),        // 0 : temperature, 1 : humidity
        .displaymode (w_displaymode),   // 현재 모드 FND,샌더 전달용
        .o_us_tick   (w_us_tick)
    );

    stopwatch U_STOPWATCH (
        .clk   (clk),
        .rst   (rst),
        .btn   (w_sw_btn),
        .o_time(w_sw_time)
    );

    watch U_WATCH (
        .clk      (clk),
        .rst      (rst),
        .btn      (w_wt_btn),
        .sw0      (w_displaymode != 2'b01),  // watch 모드가 아니면 시간 설정 X
        .sw2      (sw[2]),
        .o_time   (w_wt_time),
        .disp_mode(w_wt_disp_mode),
        .set_field(w_set_field),
        .blink_en (w_blink_en)
    );

    sr04 U_SR04 (
        .clk       (clk),
        .rst       (rst),
        .sr04_start(w_sr04_start),
        .echo      (echo),
        .trig      (trig),
        .busy      (),
        .done      (w_sr04_done),
        .timeout   (w_sr04_timeout),
        .distance  (w_distance)
    );

    dht11_module U_DHT_MODULE (
        .clk        (clk),
        .rst        (rst),
        .dht11_start(w_dht11_start),
        .us_tick    (w_us_tick),
        .valid      (w_dht11_valid),    // check sum ok
        .done       (w_dht11_done),     // 측정 완료 1클록 펄스
        .data       (w_dht11_data),     // {습도 정수, 습도 소수, 온도 정수, 온도 소수, checksum}
        .dht11_io   (dht11_io)
    );

    // dht11 fnd 표시값 : 정수 * 100 + 소수 * 10 (25.3 -> 2530)
    wire [7:0] w_dht_int = (w_sw_dth) ? w_dht11_data[39:32] : w_dht11_data[23:16];
    wire [7:0] w_dht_dec = (w_sw_dth) ? w_dht11_data[31:24] : w_dht11_data[15:8];
    wire [13:0] w_dht_fnd = w_dht_int * 7'd100 + w_dht_dec * 4'd10;

    // fnd mux 24bit
    always @(*) begin
        case (w_displaymode)
            2'b00:   fnd_data = w_sw_time;
            2'b01:   fnd_data = w_wt_time;
            2'b10:   fnd_data = {8'd0, w_distance};
            default: fnd_data = {10'd0, w_dht_fnd};
        endcase
    end

    fnd_controller U_FND_CNTL (
        .clk         (clk),
        .rst         (rst),
        .display_mode(w_displaymode),
        .mux_out     (fnd_data),
        .blink_en    (w_blink_en),
        .set_field   (w_set_field),
        .sw_disp     (sw_disp),
        .wt_disp_mode(w_wt_disp_mode),
        .fnd_com     (fnd_com),
        .fnd_font    (fnd_font)
    );

    // sender mux 40bit
    always @(*) begin
        case (w_displaymode)
            2'b00:   result_data = {16'd0, w_sw_time};
            2'b01:   result_data = {16'd0, w_wt_time};
            2'b10:   result_data = {24'd0, w_distance};
            default: result_data = w_dht11_data;
        endcase
    end

endmodule
