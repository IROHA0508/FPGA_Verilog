`timescale 1ns / 1ps

module top_dht11_module (
    input         clk,
    input         rst,
    input         start,
    input         us_tick,
    output        done,
    output        valid,
    output [39:0] data,
    inout         dht11_io
);

    dht11_module U_DHT11 (
        .clk        (clk),
        .rst        (rst),
        .dht11_start(start),  // start trigger
        .us_tick    (us_tick),
        .valid      (valid),          // check sum ok
        .done       (done),
        .data       (data),
        .dht11_io   (dht11_io)        // single wire for half duplexing
    );
endmodule

module dht11_module (
    input clk,
    input rst,
    input dht11_start,  // start trigger
    input us_tick,
    // input         disp_mode,    // 0 : temperature, 1 : humidity  (FND 표시용, 나중에 사용)
    output valid,  // check sum ok
    output done,  // 측정 완료 1클록 펄스
    // output [13:0] data,         // fnd Data : int * 100 + dec  (FND 표시용, 나중에 사용)
    output [39:0] data,         // {습도 정수, 습도 소수, 온도 정수, 온도 소수, checksum} 각 8비트
    inout dht11_io  // single wire for half duplexing
);

    localparam IDLE = 0, START = 1, WAIT = 2, SYNC_L = 3, SYNC_H = 4;
    localparam DATA_SYNC = 5, BIT = 6, STOP = 7;
    reg [2:0] c_state, n_state;

    // dht11_io_controll
    // 0 -> DHT11 sensor gets control , 1 -> FPGA board gets control
    reg dht11_io_controll_reg, dht11_io_controll_next;

    // save inout dht11_io value
    // 1 : dht11 HIGH , 0 : dht11 LOW
    reg dht11_io_reg, dht11_io_next;


    // us tick counter
    reg [$clog2(20000) - 1 : 0] tick_cnt_reg, tick_cnt_next;

    assign dht11_io = (dht11_io_controll_reg) ? dht11_io_reg : 1'bz;

    // BIT STATE
    localparam bit_criteria = 50;

    // repeat BIT State 40times
    reg [5:0] bit_cnt_reg, bit_cnt_next;
    reg [39:0] data_reg, data_next;
    reg valid_reg, valid_next;
    reg done_reg, done_next;

    // Timeout : approximate max response time * 2
    // 넘으면 센서 무응답 / 전송 중 끊김으로 보고 IDLE로 복귀 (valid = 0 유지)
    localparam SYNC_L_TIMEOUT    = 200;  // 응답 시작 지연(~10us) + 응답 LOW 80us
    localparam SYNC_H_TIMEOUT = 200;  // 응답 HIGH 80us
    localparam DATA_SYNC_TIMEOUT = 100;  // 비트 시작 LOW 50us
    localparam BIT_TIMEOUT = 150;  // 비트 HIGH 최대 70us ('1')

    // ---------------------------------------------------------------
    // 동기화기: 비동기 외부 입력 dht11_io를 clk 도메인으로 (FF 2단)
    // ---------------------------------------------------------------
    reg [1:0] io_sync;
    always @(posedge clk, posedge rst) begin
        if (rst) io_sync <= 2'b11;  // 대기 상태의 선은 HIGH
        else io_sync <= {io_sync[0], dht11_io};
    end
    wire io_s = io_sync[1];  // FSM은 이 신호만 읽는다

    wire [7:0] checksum_calc = data_reg[39:32] + data_reg[31:24]
                             + data_reg[23:16] + data_reg[15:8];
    // assign humidity    = data_reg[39:24];
    // assign temperature = data_reg[23:8];

    // ---------------------------------------------------------------
    // 출력 data : 측정에 성공한 40비트 프레임을 그대로 저장해서 내보냄
    //   [39:32] 습도 정수  [31:24] 습도 소수
    //   [23:16] 온도 정수  [15:8]  온도 소수  [7:0] checksum
    //   done과 같은 엣지에 갱신 -> done = 1인 클록에 새 data를 바로 읽을 수 있음
    //   checksum이 틀리면 갱신하지 않음 -> 직전에 성공한 프레임 유지
    // ---------------------------------------------------------------
    reg [39:0] data_out_reg;

    always @(posedge clk, posedge rst) begin
        if (rst) begin
            data_out_reg <= 40'd0;
        end else if (done_next && valid_next) begin  // done과 같은 엣지에 갱신
            data_out_reg <= data_reg;
        end
    end

    assign data  = data_out_reg;

    // ---------------------------------------------------------------
    // (FND 표시용, 나중에 사용) 정수부 * 100 + 소수부 -> 14비트 표시값
    //   사용할 때 : 포트의 disp_mode, data[13:0] 주석을 풀고
    //              위의 data[39:0] 출력 부분을 주석 처리
    // ---------------------------------------------------------------
    // reg [7:0] humid_int_reg, humid_dec_reg;
    // reg [7:0] temp_int_reg, temp_dec_reg;
    //
    // always @(posedge clk, posedge rst) begin
    //     if (rst) begin
    //         humid_int_reg <= 8'd0;
    //         humid_dec_reg <= 8'd0;
    //         temp_int_reg  <= 8'd0;
    //         temp_dec_reg  <= 8'd0;
    //     end else if (done_next && valid_next) begin  // done과 같은 엣지에 갱신
    //         humid_int_reg <= data_reg[39:32];
    //         humid_dec_reg <= data_reg[31:24];
    //         temp_int_reg  <= data_reg[23:16];
    //         temp_dec_reg  <= data_reg[15:8];
    //     end
    // end
    //
    // assign data = disp_mode ? (humid_int_reg * 14'd100 + humid_dec_reg)   // 1 : humidity
    //     : (temp_int_reg * 14'd100 + temp_dec_reg);  // 0 : temperature

    assign valid = valid_reg;
    assign done  = done_reg;

    // SL
    always @(posedge clk, posedge rst) begin
        if (rst) begin
            c_state               <= IDLE;
            dht11_io_controll_reg <= 1'b1;
            dht11_io_reg          <= 1'b1;
            tick_cnt_reg          <= 0;
            bit_cnt_reg           <= 0;
            data_reg              <= 0;
            valid_reg             <= 0;
            done_reg              <= 0;
        end else begin
            c_state               <= n_state;
            dht11_io_controll_reg <= dht11_io_controll_next;
            dht11_io_reg          <= dht11_io_next;
            tick_cnt_reg          <= tick_cnt_next;
            bit_cnt_reg           <= bit_cnt_next;
            data_reg              <= data_next;
            valid_reg             <= valid_next;
            done_reg              <= done_next;
        end
    end

    // next output
    always @(*) begin
        n_state                = c_state;
        dht11_io_controll_next = dht11_io_controll_reg;
        dht11_io_next          = dht11_io_reg;
        tick_cnt_next          = tick_cnt_reg;
        bit_cnt_next           = bit_cnt_reg;
        data_next              = data_reg;
        valid_next             = valid_reg;
        done_next              = 1'b0;  // 유지 X, 기본 0 -> 1클록 펄스

        case (c_state)
            IDLE: begin
                dht11_io_next          = 1'b1;
                dht11_io_controll_next = 1'b1;
                if (dht11_start) begin
                    tick_cnt_next = 0;
                    bit_cnt_next  = 0;
                    valid_next    = 0;
                    n_state       = START;
                end
            end

            START: begin
                dht11_io_next          = 1'b0;
                dht11_io_controll_next = 1'b1;
                if (us_tick) begin
                    // at least 18ms + margin 2 ms = 20ms
                    if (tick_cnt_reg == 20_000 - 1) begin
                        tick_cnt_next = 0;
                        n_state       = WAIT;
                    end else begin
                        tick_cnt_next = tick_cnt_reg + 1;
                    end
                end
            end

            WAIT: begin
                dht11_io_next          = 1'b1;
                dht11_io_controll_next = 1'b1;
                if (us_tick) begin
                    // range : 20 ~ 40us we chose middle of that range, so 30us
                    if (tick_cnt_reg == 30 - 1) begin
                        // change output to high impedence
                        dht11_io_controll_next = 1'b0;
                        tick_cnt_next          = 0;
                        n_state                = SYNC_L;
                    end else begin
                        tick_cnt_next = tick_cnt_reg + 1;
                    end
                end
            end

            SYNC_L: begin
                dht11_io_controll_next = 1'b0;
                if (us_tick) begin
                    if (io_s == 1'b1 && tick_cnt_reg >= 30) begin
                        tick_cnt_next = 0;
                        n_state       = SYNC_H;
                    end else if (tick_cnt_reg == SYNC_L_TIMEOUT - 1) begin
                        tick_cnt_next = 0;
                        n_state       = IDLE;
                    end else begin
                        tick_cnt_next = tick_cnt_reg + 1;
                    end
                end
            end

            SYNC_H: begin
                dht11_io_controll_next = 1'b0;
                if (io_s == 1'b0) begin
                    tick_cnt_next = 0;
                    n_state       = DATA_SYNC;
                end else if (us_tick) begin
                    if (tick_cnt_reg == SYNC_H_TIMEOUT - 1) begin
                        tick_cnt_next = 0;
                        n_state       = IDLE;
                    end else begin
                        tick_cnt_next = tick_cnt_reg + 1;
                    end
                end
            end

            DATA_SYNC: begin
                dht11_io_controll_next = 1'b0;
                if (io_s == 1'b1) begin
                    tick_cnt_next = 0;
                    n_state       = BIT;
                end else if (us_tick) begin
                    if (tick_cnt_reg == DATA_SYNC_TIMEOUT - 1) begin
                        tick_cnt_next = 0;
                        bit_cnt_next  = 0;
                        n_state       = IDLE;
                    end else begin
                        tick_cnt_next = tick_cnt_reg + 1;
                    end
                end
            end

            // tick_cnt_reg < 50  : 0
            // tick_cnt_reg >= 50 : 1
            BIT: begin
                dht11_io_controll_next = 1'b0;
                // 1 -> 0 falling edge
                if (io_s == 1'b0) begin
                    data_next = {
                        data_reg[38:0], (tick_cnt_reg >= bit_criteria)
                    };
                    tick_cnt_next = 0;

                    if (bit_cnt_reg == 40 - 1) begin
                        bit_cnt_next = 0;
                        n_state      = STOP;
                    end else begin
                        bit_cnt_next = bit_cnt_reg + 1;
                        n_state      = DATA_SYNC;
                    end
                end else if (us_tick) begin
                    if (tick_cnt_reg == BIT_TIMEOUT - 1) begin
                        tick_cnt_next = 0;
                        bit_cnt_next  = 0;
                        n_state       = IDLE;
                    end else begin
                        tick_cnt_next = tick_cnt_reg + 1;
                    end
                end
            end

            STOP: begin
                dht11_io_controll_next = 1'b0;
                if (us_tick) begin
                    // 50us
                    if (tick_cnt_reg >= 60 - 1) begin
                        dht11_io_next = 1'b1;
                        // FPGA takes control of the line again (drive HIGH)
                        dht11_io_controll_next = 1'b1;
                        tick_cnt_next = 0;
                        valid_next = (checksum_calc == data_reg[7:0]);
                        done_next = 1'b1;  // 측정 완료
                        n_state = IDLE;
                    end else begin
                        tick_cnt_next = tick_cnt_reg + 1;
                    end
                end
            end
        endcase
    end
endmodule
