`timescale 1ns / 1ps

// =====================================================================
// 최종 DHT11 모듈(dht11_module) 검증 테스트벤치
//   출력 data = 40비트 프레임 {습도 정수, 습도 소수, 온도 정수, 온도 소수, checksum}
//
//  [항상 감시]
//   - 전이 커버리지 : T1 ~ T13이 각각 한 번 이상 일어났는지
//   - L2 : SYNC_L ~ STOP(센서 구간)에서 FPGA가 선을 구동하면 FAIL
//   - L3 : IDLE / START / WAIT에서 센서 LOW와 겹치면 "알려진 한계"로 기록
//   - 타임아웃 시간 : 설정값 ±1us
//   - done : 1클록 펄스인지, done = 1인 클록에 data가 이미 새 값인지
//   - M4 : data는 done && valid인 클록에만 바뀜 (수신 중 중간값이 새지 않음)
//   - M5 : data의 checksum 필드는 항상 앞 4바이트 합과 일치
//   - M6 : valid는 done과 함께만 올라가고, START에 들어갈 때만 내려감
//   - M7 : done은 IDLE(STOP 직후)에서만 나옴
//
//  [시나리오]
//    1 정상 측정                    9 전송 중 LOW 고착 (DATA_SYNC 타임아웃)
//    2 0/1 교대 비트 + 수신 중 출력 10 측정 도중 리셋
//    3 checksum 오류               11 비트 판정 여유 (45us / 55us)
//    4 센서 응답 지연 40us         12 긴 펄스 (타임아웃 여유)
//    5 측정 중 버튼 다시 누름      13 바이트 순서 (5개 필드가 모두 다른 값)
//    6 센서 무응답 (SYNC_H 타임아웃) 14 checksum 1비트 오류
//    7 응답 LOW 고착 (SYNC_L 타임아웃) 15 연속 측정 (done 직후 바로 시작)
//    8 전송 중 HIGH로 끊김 (BIT 타임아웃) 16 checksum 8비트 넘침 (합 > 255)
//
//  Vivado: Tcl 콘솔에서 run all (약 400ms 시뮬레이션)
// =====================================================================
module tb_dht11_module ();

    // -----------------------------------------------------------------
    // 상태 번호 (dht11_controller와 같음)
    // -----------------------------------------------------------------
    localparam IDLE = 0, START = 1, WAIT = 2, SYNC_L = 3, SYNC_H = 4;
    localparam DATA_SYNC = 5, BIT = 6, STOP = 7;

    // 센서 고장 모드
    localparam F_NONE      = 0;   // 정상
    localparam F_NO_RESP   = 1;   // 무응답
    localparam F_RESP_LOW  = 2;   // 응답 LOW 고착
    localparam F_CUT_HIGH  = 3;   // N비트 후 선을 놓음 (HIGH 고정)
    localparam F_STUCK_LOW = 4;   // N비트 후 LOW 고착

    // -----------------------------------------------------------------
    // 클록, 리셋, DUT 입력
    // -----------------------------------------------------------------
    reg clk = 1'b0, rst = 1'b1, start = 1'b0;
    always #5 clk = ~clk;                       // 100MHz

    // us_tick : 100클록마다 1클록 폭 (= 1us), 리셋하면 다시 셈
    reg     us_tick = 1'b0;
    integer tick_cnt = 0;
    always @(posedge clk) begin
        if (rst) begin
            tick_cnt <= 0;
            us_tick  <= 1'b0;
        end else begin
            tick_cnt <= (tick_cnt == 99) ? 0 : tick_cnt + 1;
            us_tick  <= (tick_cnt == 99);
        end
    end

    // 단일 선 버스: 풀업 + 센서는 0을 낼 때만 끌어내림 (부록 A)
    wire dht11_io;
    reg  sensor_low = 1'b0;
    pullup (dht11_io);
    assign dht11_io = sensor_low ? 1'b0 : 1'bz;

    wire        valid;
    wire        done;
    wire [39:0] data;

    dht11_module dut (
        .clk        (clk),
        .rst        (rst),
        .dht11_start(start),
        .us_tick    (us_tick),
        .valid      (valid),
        .done       (done),
        .data       (data),
        .dht11_io   (dht11_io)
    );

    // =================================================================
    // 감시 3: done 펄스
    //   - 1클록 폭인지
    //   - done = 1인 클록에 valid와 data가 이미 이번 측정 결과인지
    // =================================================================
    integer done_cnt = 0, done_wide = 0, done_data_err = 0;
    reg     done_d = 1'b0;

    always @(posedge clk) begin
        if (!rst) begin
            if (done) begin
                done_cnt = done_cnt + 1;
                if (done_d) done_wide = done_wide + 1;
                if (valid && data != dut.data_reg) done_data_err = done_data_err + 1;
            end
            done_d = done;
        end
    end

    // =================================================================
    // 감시 4~7: 출력 인터페이스 (data / valid / done)
    //   테스트벤치는 posedge에서 "직전 엣지까지 갱신된 값"을 읽으므로,
    //   같은 엣지에 함께 바뀐 신호(data, valid, done, c_state)는 같은 클록에 함께 보임
    // =================================================================
    reg  [39:0] data_prev  = 40'd0;
    reg         valid_prev = 1'b0;
    integer     data_glitch = 0, cks_err = 0, valid_rise_err = 0, valid_fall_err = 0, done_state_err = 0;
    wire [7:0]  data_cks = data[39:32] + data[31:24] + data[23:16] + data[15:8];   // 8비트로 잘림

    always @(posedge clk) begin
        if (!rst) begin
            // M4 : data는 done && valid인 클록에만 바뀜
            if (data !== data_prev && !(done && valid)) begin
                data_glitch = data_glitch + 1;
                $display("  !! M4 data changed without done && valid at %0t : %h -> %h", $time, data_prev, data);
            end
            // M5 : 내보내는 프레임은 항상 checksum이 맞는 프레임
            if (data[7:0] !== data_cks) cks_err = cks_err + 1;
            // M6 : valid 상승은 done과 같은 클록, 하강은 START에 들어간 클록
            if ( valid && !valid_prev && !done)             valid_rise_err = valid_rise_err + 1;
            if (!valid &&  valid_prev && dut.c_state != START) valid_fall_err = valid_fall_err + 1;
            // M7 : done은 STOP -> IDLE 직후에만
            if (done && dut.c_state != IDLE) done_state_err = done_state_err + 1;
        end
        data_prev  = data;                       // 리셋 중에도 갱신 (리셋으로 바뀐 값은 오류 아님)
        valid_prev = valid;
    end

    // =================================================================
    // 감시 1: 상태 전이 기록 (커버리지, 머문 시간, 타임아웃)
    // =================================================================
    integer trans_cnt [1:13];   // T1 ~ T13 발생 횟수
    integer unexpected = 0;     // 목록에 없는 전이
    integer idle_ret   = 0;     // IDLE로 돌아온 횟수 (리셋 제외)
    real    dur_last [0:7];     // 각 상태에 마지막으로 머문 시간 (us)
    integer to_state   = -1;    // 마지막 타임아웃이 난 상태
    real    to_dur     = 0;     // 그 상태에 머문 시간 (us)
    reg [2:0] prev_state = IDLE;
    real    t_enter    = 0;
    integer i, id;

    function integer trans_id(input [2:0] from, input [2:0] to);
        case ({from, to})               // 8진수 2자리 = (출발, 도착)
            6'o01: trans_id = 1;   // T1  IDLE      -> START
            6'o12: trans_id = 2;   // T2  START     -> WAIT
            6'o23: trans_id = 3;   // T3  WAIT      -> SYNC_L
            6'o34: trans_id = 4;   // T4  SYNC_L    -> SYNC_H
            6'o30: trans_id = 5;   // T5  SYNC_L    -> IDLE (timeout)
            6'o45: trans_id = 6;   // T6  SYNC_H    -> DATA_SYNC
            6'o40: trans_id = 7;   // T7  SYNC_H    -> IDLE (timeout)
            6'o56: trans_id = 8;   // T8  DATA_SYNC -> BIT
            6'o50: trans_id = 9;   // T9  DATA_SYNC -> IDLE (timeout)
            6'o65: trans_id = 10;  // T10 BIT       -> DATA_SYNC
            6'o67: trans_id = 11;  // T11 BIT       -> STOP
            6'o60: trans_id = 12;  // T12 BIT       -> IDLE (timeout)
            6'o70: trans_id = 13;  // T13 STOP      -> IDLE
            default: trans_id = 0;
        endcase
    endfunction

    initial for (i = 1; i <= 13; i = i + 1) trans_cnt[i] = 0;
    initial for (i = 0; i <= 7;  i = i + 1) dur_last[i]  = 0;

    always @(posedge clk) begin
        if (dut.c_state != prev_state) begin
            if (!rst) begin                       // 리셋으로 인한 변화는 전이로 세지 않음
                id = trans_id(prev_state, dut.c_state);
                if (id != 0) trans_cnt[id] = trans_cnt[id] + 1;
                else begin
                    unexpected = unexpected + 1;
                    $display("  !! unexpected transition %0d -> %0d at %0t", prev_state, dut.c_state, $time);
                end
                dur_last[prev_state] = ($realtime - t_enter) / 1000.0;
                if (dut.c_state == IDLE) begin
                    idle_ret = idle_ret + 1;
                    if (prev_state >= SYNC_L && prev_state <= BIT) begin
                        to_state = prev_state;
                        to_dur   = dur_last[prev_state];
                    end
                end
            end
            prev_state = dut.c_state;
            t_enter    = $realtime;
        end
    end

    // =================================================================
    // 감시 2: 선 제어 (L2 FAIL / L3 알려진 한계)
    // =================================================================
    integer l2_err    = 0;      // 센서 구간에서 FPGA가 구동한 클록 수
    integer known_clk = 0;      // FPGA HIGH 구동 + 센서 LOW 가 겹친 클록 수

    always @(posedge clk) begin
        if (!rst) begin
            if (dut.dht11_io_controll_reg && dut.c_state >= SYNC_L) l2_err = l2_err + 1;
            if (dut.dht11_io_controll_reg && dut.dht11_io_reg && sensor_low) known_clk = known_clk + 1;
        end
    end

    // =================================================================
    // 센서 모델 (조절값은 시나리오마다 바꿈, 단위 us)
    // =================================================================
    integer resp_delay, resp_low, resp_high, bit_low, t_zero, t_one, end_low;
    integer start_low_us;       // 모델이 측정한 시작 LOW 길이
    integer k;
    time    t_fall;

    task set_default;
        begin
            resp_delay = 35;  resp_low = 80;  resp_high = 80;
            bit_low    = 50;  t_zero   = 27;  t_one     = 70;  end_low = 50;
        end
    endtask

    task sensor_run(input [39:0] d, input integer fault, input integer nbits);
        begin : body
            @(negedge dht11_io);  t_fall = $time;           // FPGA가 LOW로 끌어내림
            @(posedge dht11_io);                             // FPGA가 HIGH로 올림
            start_low_us = ($time - t_fall) / 1000;

            if (fault == F_NO_RESP) disable body;            // 아무 응답도 안 함

            #(resp_delay * 1000) sensor_low = 1'b1;          // 응답 LOW 시작
            if (fault == F_RESP_LOW) begin                   // LOW를 놓지 않음
                #500_000 sensor_low = 1'b0;
                disable body;
            end
            #(resp_low  * 1000) sensor_low = 1'b0;          // 응답 HIGH
            #(resp_high * 1000);

            for (k = 39; k >= 0; k = k - 1) begin           // MSB first
                if ((fault == F_CUT_HIGH || fault == F_STUCK_LOW) && (39 - k) == nbits) begin
                    if (fault == F_STUCK_LOW) begin
                        sensor_low = 1'b1; #400_000 sensor_low = 1'b0;
                    end
                    disable body;                            // F_CUT_HIGH : 선을 놓은 채 끝
                end
                sensor_low = 1'b1; #(bit_low * 1000);        // 비트 시작 LOW
                sensor_low = 1'b0;
                if (d[k]) #(t_one  * 1000);                  // '1' HIGH
                else      #(t_zero * 1000);                  // '0' HIGH
            end
            sensor_low = 1'b1; #(end_low * 1000);            // 끝 LOW
            sensor_low = 1'b0;                               // 선을 놓음
        end
    endtask

    // =================================================================
    // 판정 도구
    // =================================================================
    integer pass_cnt = 0, fail_cnt = 0;

    task check(input cond, input [8*64-1:0] what);
        begin
            if (cond) begin pass_cnt = pass_cnt + 1; $display("  PASS  %0s", what); end
            else      begin fail_cnt = fail_cnt + 1; $display("  FAIL  %0s", what); end
        end
    endtask

    function near(input real val, input real target, input real tol);
        near = (val >= target - tol) && (val <= target + tol);
    endfunction

    // 기대 data (마지막으로 성공한 40비트 프레임)
    reg [39:0] exp_data = 40'd0;

    task check_display;
        begin
            $display("  data : %h (exp %h)  -> humid %0d.%0d %%, temp %0d.%0d C, checksum %h",
                     data, exp_data, data[39:32], data[31:24], data[23:16], data[15:8], data[7:0]);
            check(data == exp_data, "D4/D5 data output (40-bit frame)");
        end
    endtask

    task set_expect(input [39:0] d);                         // 성공 측정이면 기대값 갱신
        begin
            exp_data = d;
        end
    endtask

    // 시나리오 시작 / 끝 (L2, L3 집계)
    integer s_l2, s_known, s_t1, s_done;   // 시나리오 시작 시점의 값 (s_done : done 개수)
    integer known_us [1:16];
    reg [8*48-1:0] scen_name [1:16];
    integer scen   = 0;
    time    scen_t0 = 0;       // 시나리오 시작 시각 (감시 타이머용)

    task scen_begin(input integer n, input [8*48-1:0] name);
        begin
            scen = n;  scen_name[n] = name;  scen_t0 = $time;
            s_l2 = l2_err;  s_known = known_clk;  s_t1 = trans_cnt[1];  s_done = done_cnt;
            to_state = -1;
            set_default;
            $display("\n[%0d] %0s", n, name);
        end
    endtask

    task scen_end;
        begin
            check(l2_err == s_l2, "L2 FPGA does not drive the line in SYNC_L..STOP");
            known_us[scen] = (known_clk - s_known) / 100;
            if (known_us[scen] > 0)
                $display("  KNOWN L3 overlap (FPGA HIGH vs sensor LOW) : %0d us", known_us[scen]);
            #1_000_000;                                      // 다음 시나리오 전 1ms
        end
    endtask

    // 버튼 1클록 펄스
    task press;
        begin @(posedge clk) start = 1'b1; @(posedge clk) start = 1'b0; end
    endtask

    // 측정 한 번: 센서 동작 + 버튼, IDLE로 돌아올 때까지 대기
    integer n0, m_done;
    task measure(input [39:0] d, input integer fault, input integer nbits);
        begin
            n0 = idle_ret;  m_done = done_cnt;
            fork
                sensor_run(d, fault, nbits);
                press;
            join
            wait (idle_ret > n0);
            repeat (10) @(posedge clk);
        end
    endtask

    // 정상 측정 결과 확인
    task check_ok(input [39:0] d);
        begin
            check(dut.data_reg == d,      "D2 40 bits received (data_reg == sent)");
            check(valid == 1'b1,          "D3 valid = 1 (checksum ok)");
            check(done_cnt == m_done + 1, "I1 one done pulse for this frame");
            set_expect(d);
            check_display;
        end
    endtask

    // checksum 오류 결과 확인 : done은 나오지만 valid = 0, data는 직전 프레임 유지
    task check_err(input [39:0] d);
        begin
            check(dut.data_reg == d,      "D2 40 bits received (data_reg == sent)");
            check(valid == 1'b0,          "D3 valid = 0 (checksum error)");
            check(done_cnt == m_done + 1, "I1 done pulse also on checksum error");
            check_display;                                   // D5: 직전 프레임 유지
        end
    endtask

    // 타임아웃 결과 확인
    task check_timeout(input integer st, input integer limit_us, input [8*64-1:0] what);
        begin
            $display("  timeout : state %0d, stayed %0.1f us (limit %0d us)", to_state, to_dur, limit_us);
            check(to_state == st,                 what);
            check(done_cnt == s_done,             "no done pulse on timeout");
            check(near(to_dur, limit_us, 1.0),    "timeout time = limit +-1us");
            check(dut.c_state == IDLE,            "back in IDLE");
            check(valid == 1'b0,                  "D3 valid = 0");
            check_display;                                   // D5: 직전 값 유지
        end
    endtask

    // =================================================================
    // 요약 출력 (정상 종료와 감시 타이머 종료에서 함께 사용)
    // =================================================================
    task print_summary;
        begin
            $display("\n================ transition coverage ================");
            for (i = 1; i <= 13; i = i + 1) begin
                $display("  T%0d : %0d", i, trans_cnt[i]);
                check(trans_cnt[i] > 0, "transition covered");
            end
            check(unexpected == 0, "no unexpected transition");

            $display("\n================ done pulse ==========================");
            $display("  done pulses %0d (STOP -> IDLE %0d)", done_cnt, trans_cnt[13]);
            check(done_cnt == trans_cnt[13], "done once per completed frame");
            check(done_wide == 0,            "done is 1 clock wide");
            check(done_data_err == 0,        "data already updated when done = 1");

            $display("\n================ output interface (M4 ~ M7) ===========");
            check(data_glitch    == 0, "M4 data changes only when done && valid");
            check(cks_err        == 0, "M5 data checksum field always consistent");
            check(valid_rise_err == 0, "M6 valid rises only together with done");
            check(valid_fall_err == 0, "M6 valid falls only on entering START");
            check(done_state_err == 0, "M7 done only in IDLE right after STOP");

            $display("\n================ known limitation (L3) ==============");
            for (i = 1; i <= 16; i = i + 1)
                if (known_us[i] > 0)
                    $display("  [%0d] %0s : overlap %0d us", i, scen_name[i], known_us[i]);

            $display("\n=====================================================");
            $display("  PASS %0d / FAIL %0d", pass_cnt, fail_cnt);
            $display("=====================================================");
        end
    endtask

    // =================================================================
    // 감시 타이머: 설계 버그로 테스트벤치가 영원히 기다리지 않도록
    //   한 시나리오가 80ms 안에 끝나지 않으면 FAIL로 보고 종료
    // =================================================================
    always #1_000_000 begin
        if (scen != 0 && $time - scen_t0 > 80_000_000) begin
            fail_cnt = fail_cnt + 1;
            $display("  FAIL  watchdog: scenario %0d did not finish within 80ms (state %0d, bit_cnt %0d)",
                     scen, dut.c_state, dut.bit_cnt_reg);
            print_summary;
            $finish;
        end
    end

    // =================================================================
    // 시나리오
    // =================================================================
    reg [39:0] d, dA, dB;

    initial begin
        set_default;
        for (i = 1; i <= 16; i = i + 1) known_us[i] = 0;
        #100;

        // ---- 리셋 상태 확인 (R1) ------------------------------------
        $display("\n[0] reset state");
        check(dut.c_state == IDLE,                                   "R1 state = IDLE");
        check(valid == 1'b0,                                          "R1 valid = 0");
        check(dut.dht11_io_controll_reg && dut.dht11_io_reg,          "R1 FPGA drives line HIGH");
        check_display;                                                // 0 / 0
        rst = 1'b0;

        // ---- 1. 정상 측정 -------------------------------------------
        scen_begin(1, "normal 55.0% / 24.3C");
        #100_000;
        check(dut.c_state == IDLE, "N1 stays IDLE without button");
        d = 40'h37_00_18_03_52;
        measure(d, F_NONE, 0);
        $display("  start LOW %0d us, WAIT %0.1f us, STOP %0.1f us",
                 start_low_us, dur_last[WAIT], dur_last[STOP]);
        check(start_low_us >= 19999 && start_low_us <= 20001, "T2 start LOW = 20000us");
        check(near(dur_last[WAIT], 30.0, 1.0),                "T3 WAIT = 30us");
        check(near(dur_last[STOP], 60.0, 1.0),                "T13 STOP = 60us");
        check_ok(d);
        scen_end;

        // ---- 2. 0/1 교대 비트 ---------------------------------------
        scen_begin(2, "alternating bits 85.0% / 42.5C");
        d = 40'h55_00_2A_05_84;
        fork
            measure(d, F_NONE, 0);
            begin                                            // 20비트째 수신 중 출력 확인
                wait (dut.bit_cnt_reg == 20);  #1;
                $display("  while receiving: data_reg=%h  data=%h  valid=%b", dut.data_reg, data, valid);
                check(valid == 1'b0,     "I2 valid = 0 while receiving");
                check(data == exp_data,  "I2 data holds previous frame while receiving");
            end
        join
        check_ok(d);
        scen_end;

        // ---- 3. checksum 오류 ---------------------------------------
        scen_begin(3, "wrong checksum");
        d = 40'h37_00_18_03_00;
        measure(d, F_NONE, 0);
        check_err(d);                                      // D5: 2번 값 유지
        scen_end;

        // ---- 4. 센서 응답 지연 40us (N2) ----------------------------
        scen_begin(4, "sensor response delay 40us");
        resp_delay = 40;
        d = 40'h2D_00_14_05_46;
        measure(d, F_NONE, 0);
        $display("  SYNC_L stayed %0.1f us (expect ~90: 10us HIGH + 80us LOW)", dur_last[SYNC_L]);
        check(near(dur_last[SYNC_L], 90.0, 5.0), "N2 SYNC_L ignores early HIGH (tick < 30)");
        check_ok(d);
        scen_end;

        // ---- 5. 측정 중 버튼 다시 누름 (N3) -------------------------
        scen_begin(5, "button pressed again during measurement");
        d = 40'h3C_00_16_02_54;
        fork
            measure(d, F_NONE, 0);
            begin
                #5_000_000  press;                           // START 도중
                #16_000_000 press;                           // 비트 수신 도중 (약 21ms)
            end
        join
        check(trans_cnt[1] - s_t1 == 1,                        "N3 IDLE -> START only once");
        check(start_low_us >= 19999 && start_low_us <= 20001,  "N3 start LOW still 20000us");
        check_ok(d);
        scen_end;

        // ---- 6. 센서 무응답 (T7) ------------------------------------
        scen_begin(6, "no response (SYNC_H timeout)");
        measure(40'h37_00_18_03_52, F_NO_RESP, 0);
        check_timeout(SYNC_H, 200, "T7 timeout in SYNC_H");
        scen_end;

        // ---- 7. 응답 LOW 고착 (T5) ----------------------------------
        scen_begin(7, "response LOW stuck (SYNC_L timeout)");
        measure(40'h37_00_18_03_52, F_RESP_LOW, 0);
        check_timeout(SYNC_L, 200, "T5 timeout in SYNC_L");
        scen_end;

        // ---- 8. 전송 중 HIGH로 끊김 (T12) ---------------------------
        scen_begin(8, "line released after 10 bits (BIT timeout)");
        measure(40'h37_00_18_03_52, F_CUT_HIGH, 10);
        check(dut.bit_cnt_reg == 0, "bit_cnt cleared");
        check_timeout(BIT, 150, "T12 timeout in BIT");
        scen_end;

        // ---- 9. 전송 중 LOW 고착 (T9) -------------------------------
        scen_begin(9, "LOW stuck after 10 bits (DATA_SYNC timeout)");
        measure(40'h37_00_18_03_52, F_STUCK_LOW, 10);
        check(dut.bit_cnt_reg == 0, "bit_cnt cleared");
        check_timeout(DATA_SYNC, 100, "T9 timeout in DATA_SYNC");
        scen_end;

        // ---- 10. 측정 도중 리셋 (R1, R2, R3) ------------------------
        scen_begin(10, "reset during measurement");
        d = 40'h37_00_18_03_52;
        fork
            sensor_run(d, F_NONE, 0);                        // 센서는 끝까지 보냄
            press;
            begin
                wait (dut.bit_cnt_reg == 20);                // 20비트째 수신 중
                @(posedge clk) #2 rst = 1'b1;
                #20;
                check(dut.c_state == IDLE,                          "R2 state = IDLE right after reset");
                check(valid == 1'b0,                                "R2 valid = 0");
                check(dut.dht11_io_controll_reg && dut.dht11_io_reg, "R2 FPGA drives line HIGH");
                exp_data = 40'd0;
                check_display;                                      // 저장값도 리셋 -> 0
                #80 rst = 1'b0;
            end
        join
        check(done_cnt == s_done, "I3 no done pulse for the aborted frame");
        #1_000_000;
        $display("  re-measure after reset");
        measure(d, F_NONE, 0);
        check_ok(d);                                                // R3: 다시 정상
        scen_end;

        // ---- 11. 비트 판정 여유 (D1) --------------------------------
        scen_begin(11, "bit margin: '0' = 45us, '1' = 55us");
        t_zero = 45;  t_one = 55;
        d = 40'h5A_00_32_09_95;
        measure(d, F_NONE, 0);
        check_ok(d);
        scen_end;

        // ---- 12. 긴 펄스 (N4) ---------------------------------------
        scen_begin(12, "long pulses (no false timeout)");
        resp_low = 90;  resp_high = 90;  bit_low = 60;
        t_zero   = 30;  t_one     = 80;  end_low = 55;
        d = 40'h28_00_19_04_45;
        measure(d, F_NONE, 0);
        check(to_state == -1, "N4 no timeout");
        check_ok(d);
        scen_end;

        // ---- 13. 바이트 순서 (5개 필드가 모두 다른 값) --------------
        //   습도 65.2%, 온도 23.8C : 41 / 02 / 17 / 08 / 62
        //   필드가 서로 다르므로 바이트 위치가 하나라도 바뀌면 바로 드러남
        scen_begin(13, "byte order: all 5 fields different");
        d = 40'h41_02_17_08_62;
        measure(d, F_NONE, 0);
        check_ok(d);
        check(data[39:32] == 8'h41, "B1 data[39:32] = humidity int  (65)");
        check(data[31:24] == 8'h02, "B2 data[31:24] = humidity dec  (2)");
        check(data[23:16] == 8'h17, "B3 data[23:16] = temperature int (23)");
        check(data[15:8]  == 8'h08, "B4 data[15:8]  = temperature dec (8)");
        check(data[7:0]   == 8'h62, "B5 data[7:0]   = checksum");
        scen_end;

        // ---- 14. checksum 1비트 오류 --------------------------------
        //   13번과 같은 프레임에서 checksum LSB만 뒤집음 (62 -> 63)
        scen_begin(14, "checksum off by 1 bit");
        d = 40'h41_02_17_08_63;
        measure(d, F_NONE, 0);
        check_err(d);                                      // 13번 프레임 유지
        scen_end;

        // ---- 15. 연속 측정 (done 직후 바로 시작) --------------------
        //   프레임 A가 끝나 done이 나온 다음 클록에 버튼 -> 프레임 B
        //   (실제 센서는 측정 간격 1초 이상이 필요 - 호출하는 쪽의 책임)
        scen_begin(15, "back-to-back: start right after done");
        dA = 40'h32_00_15_06_4D;                           // 50.0%, 21.6C
        dB = 40'h33_00_15_07_4F;                           // 51.0%, 21.7C
        fork
            sensor_run(dA, F_NONE, 0);
            press;
        join
        wait (done);                                       // 프레임 A 완료
        @(posedge clk);
        $display("  frame A done : data=%h valid=%b", data, valid);
        check(data == dA && valid == 1'b1, "C1 frame A stored at its done");
        fork
            sensor_run(dB, F_NONE, 0);
            begin
                press;  #1;                                // done 다음 클록에 start
                check(dut.c_state == START, "C2 next start accepted right after done");
                #1_000;                                    // START 진입 직후
                check(valid == 1'b0,        "C3 valid cleared at new START");
                check(data  == dA,          "C3 data still frame A during frame B");
            end
        join
        wait (done);
        @(posedge clk);
        $display("  frame B done : data=%h valid=%b", data, valid);
        check(data == dB && valid == 1'b1, "C4 frame B replaces frame A");
        check(done_cnt == s_done + 2,      "C5 two done pulses for two frames");
        set_expect(dB);
        scen_end;

        // ---- 16. checksum 8비트 넘침 --------------------------------
        //   C8 + 10 + 30 + 09 = 0x111 -> 하위 8비트 0x11
        //   (DHT11 측정 범위 밖의 값이지만 checksum 계산이 8비트로 잘리는지 확인)
        scen_begin(16, "checksum wrap (sum > 255)");
        d = 40'hC8_10_30_09_11;
        measure(d, F_NONE, 0);
        check_ok(d);
        scen_end;

        print_summary;
        $finish;
    end

endmodule