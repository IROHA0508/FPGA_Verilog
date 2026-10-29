`timescale 1ns / 1ps
// =====================================================================
// tb_eval_stress.v
//   평가용 자체 판정 테스트벤치 : P4(장시간·랜덤 스트레스)
//   DUT : stopwatch_watch_integrate (설계 소스는 수정하지 않음, defparam만 사용)
//
//   시간 축소 (04 K-05 합의값, 세 상수 비율 유지)
//     F_COUNT    1,000,000   -> 10      (10 ms 틱 = 10 clk, 1 h = 3,600,000 clk = 36 ms)
//     HOLD_COUNT 300,000,000 -> 3,000   (3 s    = 300 틱)
//     HALF_COUNT 25,000,000  -> 250     (0.25 s = 25 틱)
//     btn_debounce(1 MHz 샘플, 8 us)와 clk_div_800hz는 리터럴이라 축소하지 않음
//
//   진행 : 1시간 구간마다
//     (1) 랜덤 자극 : sw0/sw1 무작위 전환, sw0=0(Watch IDLE)일 때 무작위 버튼 (두 모드 모두 무시해야 함)
//     (2) 정확도 판정 : Watch, Stopwatch 값 = 구간 시작값 + 경과 클럭/F_COUNT 틱 (오차 0)
//     (3) 기능 묶음 : P1(W-01~04, S-01~04, C-01~03), P3(디바운스, 언더플로, R-08) 재수행
//   출력 : "RESULT P4 HOUR n : PASS/FAIL", 마지막에 "SUMMARY" 한 줄
//   시간 변경 : 파라미터 HOURS (기본 6). 24/48/96시간은 HOURS=24/48/96
//               Vivado: Simulation Settings > Generics/Parameters 에 HOURS=24
// =====================================================================
module tb_eval_stress #(parameter integer HOURS = 24);

    localparam F_CNT       = 10;
    localparam HOLD        = 3_000;
    localparam HALF        = 250;
    localparam BTN_HIGH_NS = 20_000;     // 20 us 누름 (> 8 us)
    localparam BTN_LOW_NS  = 20_000;     // 20 us 뗌
    localparam SYNC_GUARD  = 4*F_CNT + 3000;
    localparam BR = 0, BL = 1, BU = 2, BD = 3;

    // ---------------- DUT ----------------
    reg        clk = 1'b0, rst = 1'b1;
    reg        btnR = 0, btnL = 0, btnU = 0, btnD = 0;
    reg  [2:0] sw = 3'b000;
    wire [3:0] fnd_com;
    wire [7:0] fnd_font;
    wire [1:0] led;

    stopwatch_watch_integrate dut (
        .clk(clk), .rst(rst),
        .btnR(btnR), .btnL(btnL), .btnU(btnU), .btnD(btnD),
        .sw(sw), .fnd_com(fnd_com), .fnd_font(fnd_font), .led(led)
    );

    defparam dut.U_WATCH.U_WATCH_DATATPATH.U_TICK_GEN_100HMZ.F_COUNT         = F_CNT;
    defparam dut.U_STOPWATCH.U_STOPWATCH_DATATPATH.U_TICK_GEN_100HMZ.F_COUNT = F_CNT;
    defparam dut.U_STOPWATCH.U_LAP_MODULE.HOLD_COUNT                         = HOLD;
    defparam dut.U_FND_CNTL.U_BLINK.HALF_COUNT                               = HALF;

    always #5 clk = ~clk;   // 100 MHz

    // ---------------- 관찰 신호 ----------------
    wire [23:0] wt       = dut.w_wt_time;                       // watch 출력
    wire [23:0] sw_disp  = dut.w_sw_time;                       // stopwatch 출력 (LAP mux 이후)
    wire [23:0] sw_live  = {dut.U_STOPWATCH.w_live_hour, dut.U_STOPWATCH.w_live_min,
                            dut.U_STOPWATCH.w_live_sec,  dut.U_STOPWATCH.w_live_msec};
    wire        sw_run   = dut.U_STOPWATCH.w_run_stop;
    wire        sw_mode  = dut.U_STOPWATCH.w_mode;
    wire        lap_hold = dut.U_STOPWATCH.U_LAP_MODULE.hold;
    wire        btn_lap  = dut.U_STOPWATCH.U_LAP_MODULE.btn_lap;
    wire [2:0]  set_field = dut.w_set_field;
    wire        blink_en = dut.w_blink_en;
    wire        blink_on = dut.U_FND_CNTL.w_blink_on;
    wire [2:0]  ds_sel   = dut.U_FND_CNTL.w_ds_sel;

    // ---------------- 시간 변환 ----------------
    function integer to_cs(input [23:0] t);
        to_cs = t[23:19]*360000 + t[18:13]*6000 + t[12:7]*100 + t[6:0];
    endfunction

    function [23:0] from_cs(input integer cs);
        integer c;
        begin
            c = cs % 8640000;
            if (c < 0) c = c + 8640000;
            from_cs[23:19] = c / 360000;
            from_cs[18:13] = (c / 6000) % 60;
            from_cs[12:7]  = (c / 100) % 60;
            from_cs[6:0]   = c % 100;
        end
    endfunction

    function [23:0] add_cs(input [23:0] t, input integer k);
        add_cs = from_cs(to_cs(t) + k);
    endfunction

    function [23:0] hmsc(input integer h, input integer m, input integer s, input integer c);
        hmsc = from_cs(h*360000 + m*6000 + s*100 + c);
    endfunction

    // ---------------- 판정 공통 ----------------
    integer n_pass = 0, n_fail = 0, tc_err = 0;
    reg [8*24-1:0] tc_name;
    integer mon_err = 0, mon_snap = 0;
    integer seed = 32'h5EED_0004;

    task pt(input [23:0] t);
        $write("%02d:%02d:%02d.%02d", t[23:19], t[18:13], t[12:7], t[6:0]);
    endtask

    task tc_begin(input [8*24-1:0] name);
        begin
            tc_name = name; tc_err = 0; mon_snap = mon_err;
            $display("[%0t] ==== %0s", $time, name);
        end
    endtask

    task tc_end;
        begin
            if (mon_err != mon_snap) begin
                tc_err = tc_err + (mon_err - mon_snap);
                $display("[%0t]   ERROR FND/LED monitor mismatches = %0d", $time, mon_err - mon_snap);
            end
            if (tc_err == 0) begin
                n_pass = n_pass + 1;
                $display("[%0t] RESULT %0s : PASS", $time, tc_name);
            end else begin
                n_fail = n_fail + 1;
                $display("[%0t] RESULT %0s : FAIL (errors=%0d)", $time, tc_name, tc_err);
            end
        end
    endtask

    task chk(input ok, input [8*64-1:0] msg);
        if (ok !== 1'b1) begin
            tc_err = tc_err + 1;
            $display("[%0t]   ERROR %0s", $time, msg);
        end
    endtask

    task chk_i(input integer act, input integer exp, input [8*64-1:0] msg);
        if (act !== exp) begin
            tc_err = tc_err + 1;
            $display("[%0t]   ERROR %0s : act=%0d exp=%0d", $time, msg, act, exp);
        end
    endtask

    task chk_t(input [23:0] act, input [23:0] exp, input [8*64-1:0] msg);
        if (act !== exp) begin
            tc_err = tc_err + 1;
            $write("[%0t]   ERROR %0s : act=", $time, msg); pt(act);
            $write(" exp="); pt(exp); $write("\n");
        end
    endtask

    // ---------------- 사이클 카운터 / 펄스 카운터 ----------------
    integer cyc = 0;
    always @(posedge clk) cyc <= cyc + 1;

    integer pc [0:3];
    integer k_pc;
    initial for (k_pc = 0; k_pc < 4; k_pc = k_pc + 1) pc[k_pc] = 0;
    always @(posedge clk) begin
        #1;
        if (!rst)
            for (k_pc = 0; k_pc < 4; k_pc = k_pc + 1)
                if (dut.U_BTN_DEBOUNCE.w_btn[k_pc] === 1'b1) pc[k_pc] = pc[k_pc] + 1;
    end

    // ---------------- LAP 모니터 ----------------
    // btn_lap 펄스가 보이는 negedge의 live 값 = 다음 posedge에 캡처되는 값
    integer     lap_cap_cyc = -1, hold_fall_cyc = -1, lap_events = 0;
    reg  [23:0] lap_val = 24'd0;
    reg         hold_d = 1'b0;
    always @(negedge clk)
        if (!rst && btn_lap === 1'b1) begin
            lap_cap_cyc = cyc + 1;
            lap_val     = sw_live;
            lap_events  = lap_events + 1;
        end
    always @(posedge clk) begin
        #1;
        if (hold_d === 1'b1 && lap_hold === 1'b0) hold_fall_cyc = cyc;
        hold_d = lap_hold;
    end

    // ---------------- FND / LED 기준 모델 모니터 ----------------
    // 01 문서 5-4, 6-2 R-06, R-14 기준. posedge+1 ns마다 비교.
    reg  [7:0]  font_tab [0:15];
    reg         mon_en = 1'b0;
    reg  [23:0] m_t;
    reg         m_sel, m_hide;
    reg  [3:0]  m_val, m_com;
    reg  [7:0]  m_exp;
    initial begin
        font_tab[0] = 8'hc0; font_tab[1] = 8'hf9; font_tab[2]  = 8'ha4; font_tab[3]  = 8'hb0;
        font_tab[4] = 8'h99; font_tab[5] = 8'h92; font_tab[6]  = 8'h82; font_tab[7]  = 8'hf8;
        font_tab[8] = 8'h80; font_tab[9] = 8'h90; font_tab[10] = 8'hff; font_tab[11] = 8'hff;
        font_tab[12] = 8'hff; font_tab[13] = 8'hff; font_tab[14] = 8'hff; font_tab[15] = 8'hff;
    end
    always @(posedge clk) begin
        #1;
        if (mon_en && !rst) begin
            m_t   = sw[0] ? dut.w_sw_time : dut.w_wt_time;
            m_com = ~(4'b0001 << ds_sel[1:0]);
            if (blink_en) m_sel = (set_field != 3'b101);   // SET_SEC -> Sec/Msec, SET_MIN/HOUR -> Hour/Min
            else          m_sel = sw[1];
            if (ds_sel == 3'd6)
                m_exp = (blink_en || m_t[6:0] < 50) ? 8'h7f : 8'hff;   // 소수점
            else if (ds_sel[2])
                m_exp = 8'hff;                                       // 4,5,7 소등
            else begin
                case ({m_sel, ds_sel[1:0]})
                    3'b000: m_val = m_t[6:0]   % 10;
                    3'b001: m_val = m_t[6:0]   / 10;
                    3'b010: m_val = m_t[12:7]  % 10;
                    3'b011: m_val = m_t[12:7]  / 10;
                    3'b100: m_val = m_t[18:13] % 10;
                    3'b101: m_val = m_t[18:13] / 10;
                    3'b110: m_val = m_t[23:19] % 10;
                    default: m_val = m_t[23:19] / 10;
                endcase
                m_hide = blink_en && (blink_on === 1'b0) &&
                         ( (set_field == 3'b101 && m_sel == 1'b0 &&  ds_sel[1]) ||
                           (set_field == 3'b110 && m_sel == 1'b1 && !ds_sel[1]) ||
                           (set_field == 3'b111 && m_sel == 1'b1 &&  ds_sel[1]) );
                m_exp = m_hide ? 8'hff : font_tab[m_val];
            end
            if (fnd_com !== m_com || fnd_font !== m_exp || led[0] !== m_sel || led[1] !== ~sw[0]) begin
                mon_err = mon_err + 1;
                if (mon_err <= 20)
                    $display("[%0t]   MON mismatch ds_sel=%0d com=%b(exp %b) font=%h(exp %h) led=%b(exp %b%b)",
                             $time, ds_sel, fnd_com, m_com, fnd_font, m_exp, led, ~sw[0], m_sel);
            end
        end
    end

    // ---------------- 자극 태스크 ----------------
    task wclk(input integer n);
        begin repeat (n) @(posedge clk); #2; end
    endtask

    task wtick(input integer n);
        begin repeat (n*F_CNT) @(posedge clk); #2; end
    endtask

    task set_sw(input integer i, input v);
        begin @(negedge clk); sw[i] = v; end
    endtask

    task drive(input [3:0] mask, input v);
        begin
            if (mask[0]) btnR = v;
            if (mask[1]) btnL = v;
            if (mask[2]) btnU = v;
            if (mask[3]) btnD = v;
        end
    endtask

    // mask 버튼들을 같은 시각에 high_ns 동안 누름 (off_ns: 샘플 위상 변경용 지연)
    task press_m(input [3:0] mask, input integer high_ns, input integer off_ns);
        begin
            @(negedge clk);
            if (off_ns > 0) #(off_ns);
            drive(mask, 1'b1);
            #(high_ns);
            drive(mask, 1'b0);
            #(BTN_LOW_NS);
            @(negedge clk);
        end
    endtask

    task tap(input integer b);
        press_m(4'b0001 << b, BTN_HIGH_NS, 0);
    endtask

    // 틱 직후 5클럭(리플 캐리 정착) 위치로 정렬
    task sync_wt;
        integer g; reg [6:0] m0;
        begin
            @(posedge clk); #2; m0 = wt[6:0]; g = 0;
            while (wt[6:0] == m0 && g < SYNC_GUARD) begin @(posedge clk); #2; g = g + 1; end
            if (g >= SYNC_GUARD) begin tc_err = tc_err + 1; $display("[%0t]   ERROR sync_wt: watch did not advance", $time); end
            repeat (5) @(posedge clk); #2;
        end
    endtask

    task sync_sw;
        integer g; reg [6:0] m0;
        begin
            @(posedge clk); #2; m0 = sw_live[6:0]; g = 0;
            while (sw_live[6:0] == m0 && g < SYNC_GUARD) begin @(posedge clk); #2; g = g + 1; end
            if (g >= SYNC_GUARD) begin tc_err = tc_err + 1; $display("[%0t]   ERROR sync_sw: stopwatch did not advance", $time); end
            repeat (5) @(posedge clk); #2;
        end
    endtask

    task wait_hold_end;
        integer g;
        begin
            g = 0;
            while (lap_hold === 1'b1 && g < 3*HOLD) begin @(posedge clk); #2; g = g + 1; end
            wclk(1);
        end
    endtask

    // STOP 상태에서만 사용 (카운터 직접 설정)
    task sw_force(input integer h, input integer m, input integer s, input integer c);
        begin
            @(negedge clk);
            dut.U_STOPWATCH.U_STOPWATCH_DATATPATH.U_HOUR_COUNTER.counter_reg = h;
            dut.U_STOPWATCH.U_STOPWATCH_DATATPATH.U_MIN_COUNTER.counter_reg  = m;
            dut.U_STOPWATCH.U_STOPWATCH_DATATPATH.U_SEC_COUNTER.counter_reg  = s;
            dut.U_STOPWATCH.U_STOPWATCH_DATATPATH.U_MSEC_COUNTER.counter_reg = c;
            wclk(1);
        end
    endtask

    task sw_stop;      if (sw_run === 1'b1) tap(BR);  endtask
    task sw_mode_up;   begin sw_stop; if (sw_mode === 1'b1) tap(BU); end endtask

    // Watch 설정 모드: 현재 선택 필드를 fld(0 sec, 1 min, 2 hour)의 target 값으로 이동
    task wt_goto(input integer fld, input integer target);
        integer cur, md, up, i;
        begin
            wclk(1);
            case (fld)
                0: begin cur = wt[12:7];  md = 60; end
                1: begin cur = wt[18:13]; md = 60; end
                default: begin cur = wt[23:19]; md = 24; end
            endcase
            up = (target - cur + md) % md;
            if (up <= md/2) for (i = 0; i < up; i = i + 1) tap(BU);
            else            for (i = 0; i < md - up; i = i + 1) tap(BD);
        end
    endtask

    // 설정 모드에서 버튼 1회 -> 선택 필드만 d(+1/-1) 순환 변경, 나머지 자리 불변, 펄스 1개
    task tap_chk(input integer b, input integer fld, input integer d);
        reg [23:0] bef, ex; integer v, md, p0;
        begin
            wclk(1); bef = wt; ex = bef; p0 = pc[b];
            md = (fld == 2) ? 24 : 60;
            case (fld) 0: v = bef[12:7]; 1: v = bef[18:13]; default: v = bef[23:19]; endcase
            v = (v + d + md) % md;
            case (fld) 0: ex[12:7] = v; 1: ex[18:13] = v; default: ex[23:19] = v; endcase
            tap(b);
            wclk(1);
            chk_t(wt, ex, "SET inc/dec result");
            chk_i(pc[b] - p0, 1, "one debounced pulse per press");
        end
    endtask

    // FND 한 프레임(ds_sel 0~7) 캡처
    reg [7:0] fr_font [0:7];
    reg [3:0] fr_com  [0:7];
    task capture_frame;
        integer k, g;
        begin
            for (k = 0; k < 8; k = k + 1) begin
                g = 0;
                while (ds_sel != k && g < 1_100_000) begin @(posedge clk); #2; g = g + 1; end
                repeat (100) @(posedge clk); #2;
                fr_font[k] = fnd_font; fr_com[k] = fnd_com;
            end
        end
    endtask

    task chk_frame(input [7:0] e0, input [7:0] e1, input [7:0] e2, input [7:0] e3, input [7:0] e6);
        integer k; reg [7:0] ef;
        begin
            for (k = 0; k < 8; k = k + 1) begin
                case (k) 0: ef = e0; 1: ef = e1; 2: ef = e2; 3: ef = e3; 6: ef = e6; default: ef = 8'hff; endcase
                if (fr_font[k] !== ef || fr_com[k] !== ~(4'b0001 << k[1:0])) begin
                    tc_err = tc_err + 1;
                    $display("[%0t]   ERROR frame ds_sel=%0d font=%h(exp %h) com=%b(exp %b)",
                             $time, k, fr_font[k], ef, fr_com[k], ~(4'b0001 << k[1:0]));
                end
            end
        end
    endtask

    // ---------------- 시나리오 (P4) ----------------
    localparam integer CYC_PER_HOUR = 360000 * F_CNT;

    reg  [23:0] t0, t1, a, f, w_ref, s_ref;
    reg  [8*24-1:0] nm;
    integer     h, n, p, e0, cw, cs, hs, h_pass = 0, h_fail = 0;

    // LAP 유지 구간 표시 모니터 : hold=1인 모든 클럭에서 표시값 = 캡처값
    integer lap_mis = 0;
    always @(posedge clk) begin
        #1;
        if (!rst && lap_hold === 1'b1 && sw_disp !== lap_val) begin
            lap_mis = lap_mis + 1;
            if (lap_mis <= 5) begin
                $write("[%0t]   LAP mismatch disp=", $time); pt(sw_disp);
                $write(" lap="); pt(lap_val); $write("\n");
            end
        end
    end

    // (1) 1시간 구간 랜덤 자극
    task random_hour(input integer start_cyc);
        integer r, op;
        begin
            while (cyc < start_cyc + CYC_PER_HOUR) begin
                r = {$random(seed)} % 200000 + 1000;
                if (cyc + r > start_cyc + CYC_PER_HOUR) r = start_cyc + CYC_PER_HOUR - cyc;
                if (r < 1) r = 1;
                repeat (r) @(negedge clk);
                op = {$random(seed)} % 4;
                case (op)
                    0: sw[0] = ~sw[0];
                    1: sw[1] = ~sw[1];
                    2: if (sw[0] == 1'b0) tap({$random(seed)} % 4);
                    default: ;
                endcase
            end
            @(negedge clk); sw = 3'b000;
        end
    endtask

    // (3) 기능 묶음
    task mini_suite;
        begin
            // ---- Watch : C-03, W-01~W-04, R-08 ----
            set_sw(0, 1'b0); set_sw(1, 1'b0); set_sw(2, 1'b1); wclk(2);
            chk(set_field == 3'b101 && blink_en == 1'b1, "C-03 sw2=1 -> SET_SEC");
            f = wt; wtick(50); chk_t(wt, f, "C-03 frozen in SET");
            tap_chk(BU, 0, 1);  tap_chk(BD, 0, -1);
            tap(BL); chk(set_field == 3'b110, "W-03 SEC -L-> MIN");
            tap_chk(BU, 1, 1);  tap_chk(BD, 1, -1);
            tap(BL); chk(set_field == 3'b111, "W-03 MIN -L-> HOUR");
            tap_chk(BU, 2, 1);  tap_chk(BD, 2, -1);
            tap(BR); chk(set_field == 3'b110, "W-03 HOUR -R-> MIN");
            tap(BR); chk(set_field == 3'b101, "W-03 MIN -R-> SEC");
            wclk(1); t0 = wt; p = pc[BU];
            press_m(4'b0100, 2_000_000, 0);
            wclk(1); chk_i(pc[BU] - p, 1, "W-04 2 ms press -> 1 pulse");
            t1 = t0; t1[12:7] = (t0[12:7] + 1) % 60; chk_t(wt, t1, "W-04 +1 once");
            tap_chk(BD, 0, -1);
            set_sw(0, 1'b1); wclk(1); chk(set_field == 3'b000, "R-08 sw0=1 -> IDLE");
            set_sw(0, 1'b0); wclk(1); chk(set_field == 3'b101, "R-08 re-entry at SET_SEC");
            wclk(1); f = wt;
            set_sw(2, 1'b0);
            sync_wt; chk_t(wt, add_cs(f, 1), "C-03 resume from frozen value");
            set_sw(1, 1'b1); wclk(300); set_sw(1, 1'b0); wclk(300);      // C-02 (FND 모니터)
            // ---- Stopwatch : C-01, S-01~S-04, P3 ----
            set_sw(0, 1'b1); wclk(1);
            chk(sw_run == 1'b1, "C-01 stopwatch still RUN after watch operations");
            e0 = lap_events; p = lap_mis; tap(BD);          // tap(40 us)이 HOLD(30 us)보다 길어 유지 구간은 모니터로 판정
            chk_i(lap_events, e0 + 1, "S-04 LAP accepted");
            wait_hold_end;
            chk_i(lap_mis - p, 0, "S-04 display = lap value during whole hold");
            chk_i(hold_fall_cyc - lap_cap_cyc, HOLD, "S-04 hold = 3 s");
            chk_t(sw_disp, sw_live, "S-04 back to live");
            tap(BR); chk(sw_run == 1'b0, "S-01 RUN -> STOP");
            wclk(1); a = sw_live; wtick(30); chk_t(sw_live, a, "S-01 frozen in STOP");
            p = pc[BD]; press_m(4'b1000, 6000, 2);  chk_i(pc[BD] - p, 0, "P3 6 us rejected");
            p = pc[BD]; press_m(4'b1000, 9000, 2);  chk_i(pc[BD] - p, 1, "P3 9 us accepted");
            tap(BL); chk_t(sw_live, 24'd0, "S-03 CLEAR");
            tap(BU); chk(sw_mode == 1'b1, "S-02 Count Down");
            fork
                tap(BR);
                begin
                    wait (sw_run === 1'b1);
                    n = 0;
                    while (sw_live == 24'd0 && n < 4*F_CNT) begin @(posedge clk); #2; n = n + 1; end
                    repeat (5) @(posedge clk); #2;
                    chk_t(sw_live, hmsc(23,59,59,99), "P3 underflow 00:00:00.00 -> 23:59:59.99");
                end
            join
            sync_sw; a = sw_live; wtick(20); chk_t(sw_live, add_cs(a, -20), "S-02 down 20 ticks");
            tap(BR); tap(BU); chk(sw_mode == 1'b0, "S-02 Count Up"); tap(BL);
            tap(BR); chk(sw_run == 1'b1, "S-01 STOP -> RUN");
            sync_sw; a = sw_live; wtick(20); chk_t(sw_live, add_cs(a, 20), "S-01 up 20 ticks");
            set_sw(0, 1'b0);                                 // stopwatch는 RUN 상태로 다음 구간 진행
        end
    endtask

    initial begin
        #((HOURS * 50 + 20) * 64'd1_000_000);
        $display("[%0t] TIMEOUT", $time);
        $display("SUMMARY tb_eval_stress : hours=%0d hour_pass=%0d hour_fail=%0d (TIMEOUT)", HOURS, h_pass, h_fail);
        $finish;
    end

    initial begin
        $display("tb_eval_stress start : HOURS=%0d F_CNT=%0d HOLD=%0d HALF=%0d (1 h = %0d clk)",
                 HOURS, F_CNT, HOLD, HALF, CYC_PER_HOUR);
        rst = 1'b1; sw = 3'b000;
        repeat (10) @(negedge clk);
        rst = 1'b0;

        tc_begin("P4 setup");
        set_sw(0, 1'b1); tap(BR); chk(sw_run == 1'b1, "stopwatch RUN (Count Up)"); set_sw(0, 1'b0);
        sync_wt; w_ref = wt;      cw = cyc;
        sync_sw; s_ref = sw_live; cs = cyc;
        tc_end;

        for (h = 1; h <= HOURS; h = h + 1) begin
            $sformat(nm, "P4 HOUR %0d", h);
            tc_begin(nm);
            mon_en = 1'b0;
            hs = cyc;
            random_hour(hs);
            sync_wt; chk_t(wt,      add_cs(w_ref, (cyc - cw) / F_CNT), "watch exact over 1 h segment");
            sync_sw; chk_t(sw_live, add_cs(s_ref, (cyc - cs) / F_CNT), "stopwatch exact over 1 h segment");
            $write("[%0t]   hour %0d : watch=", $time, h); pt(wt);
            $write("  stopwatch="); pt(sw_live); $write("\n");
            mon_en = 1'b1;
            mini_suite;
            mon_en = 1'b0;
            sync_wt; w_ref = wt;      cw = cyc;
            sync_sw; s_ref = sw_live; cs = cyc;
            tc_end;
            if (tc_err == 0) h_pass = h_pass + 1; else h_fail = h_fail + 1;
        end

        $display("SUMMARY tb_eval_stress : hours=%0d hour_pass=%0d hour_fail=%0d", HOURS, h_pass, h_fail);
        $finish;
    end

endmodule