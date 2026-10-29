`timescale 1ns / 1ps
// =====================================================================
// tb_eval_func.v
//   평가용 자체 판정 테스트벤치 : P1(6-1 기능 11개) + P3(엣지 케이스)
//   DUT : stopwatch_watch_integrate (설계 소스는 수정하지 않음, defparam만 사용)
//
//   시간 축소 (1/10,000, 세 상수의 비율 유지)
//     F_COUNT    1,000,000   -> 100     (10 ms 틱 = 100 clk = 1 us)
//     HOLD_COUNT 300,000,000 -> 30,000  (3 s    = 300 틱)
//     HALF_COUNT 25,000,000  -> 2,500   (0.25 s = 25 틱)
//     btn_debounce(1 MHz 샘플, 8 us)와 clk_div_800hz는 리터럴이라 축소하지 않음
//
//   출력 : 각 TC마다 "RESULT <ID> : PASS/FAIL", 마지막에 "SUMMARY" 한 줄
//   Vivado : Simulation Sources에 추가 -> Top 지정 -> Run Simulation 후 "run all"
// =====================================================================
module tb_eval_func;

    localparam F_CNT       = 100;
    localparam HOLD        = 30_000;
    localparam HALF        = 2_500;
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
    integer seed = 32'h5EED_0001;

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

    // ---------------- 시나리오 ----------------
    reg  [23:0] t0, t1, a, f, lv, lv2, frozen, s0;
    integer     i, n, r, p, e0, cw0, cs0, cap1, cap2, f1;
    reg         m0;

    initial begin
        #(800_000_000);
        $display("[%0t] TIMEOUT", $time);
        $display("SUMMARY tb_eval_func : pass=%0d fail=%0d (TIMEOUT)", n_pass, n_fail);
        $finish;
    end

    initial begin
        $display("tb_eval_func start : F_CNT=%0d HOLD=%0d HALF=%0d", F_CNT, HOLD, HALF);
        rst = 1'b1; sw = 3'b000;
        repeat (10) @(negedge clk);
        rst = 1'b0;
        mon_en = 1'b1;

        // ===== P3 E-01 : R-04 리셋 직후 상태 =====
        tc_begin("P3 E-01 R-04");
        wclk(1);
        chk_t(wt, hmsc(12,0,0,0), "watch reset value 12:00:00.00");
        chk_t(sw_live, 24'd0, "stopwatch reset value");
        chk_t(sw_disp, 24'd0, "stopwatch display reset value");
        chk(sw_run  == 1'b0, "stopwatch STOP after reset");
        chk(sw_mode == 1'b0, "stopwatch Count Up after reset");
        chk(lap_hold == 1'b0, "LAP hold released after reset");
        chk(set_field == 3'b000 && blink_en == 1'b0, "watch IDLE after reset");
        sync_wt; t0 = wt; wtick(50);
        chk_t(wt, add_cs(t0, 50), "watch runs right after reset");
        tc_end;

        // 준비: stopwatch RUN (C-03에서 다른 모드 영향 없음 확인용)
        set_sw(0, 1'b1); tap(BR); set_sw(0, 1'b0);

        // ===== P1 C-03a : 설정 모드 진입, 정지, 깜빡임(R-06) =====
        tc_begin("P1 C-03a SET entry");
        sync_sw; s0 = sw_live; cs0 = cyc;
        set_sw(2, 1'b1);
        @(posedge clk); #2;
        chk(set_field == 3'b101 && blink_en == 1'b1, "sw2=1 -> SET_SEC");
        chk(blink_on == 1'b1, "blink starts ON");
        n = 0; while (blink_on == 1'b1 && n < 3*HALF) begin @(posedge clk); #2; n = n + 1; end
        chk_i(n, HALF, "blink ON length (clk) = 0.25 s");
        n = 0; while (blink_on == 1'b0 && n < 3*HALF) begin @(posedge clk); #2; n = n + 1; end
        chk_i(n, HALF, "blink OFF length (clk) = 0.25 s");
        f = wt; wtick(300);
        chk_t(wt, f, "watch frozen in SET (300 ticks)");
        tc_end;

        // ===== P1 W-01 : 설정 모드 Btn U =====
        tc_begin("P1 W-01 SET +1");
        tap_chk(BU, 0, 1);
        wt_goto(0, 59); tap_chk(BU, 0, 1);                // sec 59 -> 00, 분 불변
        tap(BL); chk(set_field == 3'b110, "move to SET_MIN");
        tap_chk(BU, 1, 1);
        wt_goto(1, 59); tap_chk(BU, 1, 1);                // min 59 -> 00, 시 불변
        tap(BL); chk(set_field == 3'b111, "move to SET_HOUR");
        tap_chk(BU, 2, 1);
        wt_goto(2, 23); tap_chk(BU, 2, 1);                // hour 23 -> 00
        tc_end;

        // ===== P1 W-02 : 설정 모드 Btn D =====
        tc_begin("P1 W-02 SET -1");
        wt_goto(2, 0);  tap_chk(BD, 2, -1);               // hour 00 -> 23
        tap_chk(BD, 2, -1);                               // 23 -> 22
        tap(BR); chk(set_field == 3'b110, "move to SET_MIN");
        wt_goto(1, 0);  tap_chk(BD, 1, -1);               // min 00 -> 59, 시 불변
        tap(BR); chk(set_field == 3'b101, "move to SET_SEC");
        wt_goto(0, 0);  tap_chk(BD, 0, -1);               // sec 00 -> 59, 분 불변
        tap_chk(BD, 0, -1);
        tc_end;

        // ===== P1 W-03 : 자리 이동 =====
        tc_begin("P1 W-03 field move");
        t0 = wt;
        tap(BL); chk(set_field == 3'b110, "SEC -L-> MIN");
        tap(BL); chk(set_field == 3'b111, "MIN -L-> HOUR");
        tap(BL); chk(set_field == 3'b101, "HOUR -L-> SEC");
        tap(BR); chk(set_field == 3'b111, "SEC -R-> HOUR");
        tap(BR); chk(set_field == 3'b110, "HOUR -R-> MIN");
        tap(BR); chk(set_field == 3'b101, "MIN -R-> SEC");
        wclk(1); chk_t(wt, t0, "time unchanged by field move");
        tc_end;

        // ===== P1 W-04 : 길게 누름 =====
        tc_begin("P1 W-04 long press");
        wclk(1); t0 = wt; p = pc[BU];
        press_m(4'b0100, 5_000_000, 0);                   // 5 ms 누름
        wclk(1);
        chk_i(pc[BU] - p, 1, "5 ms press on U -> 1 pulse");
        t1 = t0; t1[12:7] = (t0[12:7] + 1) % 60;
        chk_t(wt, t1, "sec +1 only once");
        t0 = wt; p = pc[BD];
        press_m(4'b1000, 5_000_000, 0);
        wclk(1);
        chk_i(pc[BD] - p, 1, "5 ms press on D -> 1 pulse");
        t1 = t0; t1[12:7] = (t0[12:7] + 59) % 60;
        chk_t(wt, t1, "sec -1 only once");
        tc_end;

        // ===== P1 C-03b : 설정 해제, 재개, 다른 모드 독립 =====
        tc_begin("P1 C-03b SET exit");
        wclk(1); f = wt;
        set_sw(2, 1'b0);
        @(posedge clk); #2;
        chk(set_field == 3'b000 && blink_en == 1'b0, "sw2=0 -> IDLE");
        chk_t(wt, f, "value kept on exit (msec not cleared)");
        sync_wt;
        chk_t(wt, add_cs(f, 1), "resumes from frozen value (+1 tick)");
        t0 = wt; wtick(100);
        chk_t(wt, add_cs(t0, 100), "watch running after exit");
        sync_sw;
        chk_t(sw_live, add_cs(s0, (cyc - cs0) / F_CNT), "stopwatch kept running during SET");
        tc_end;

        // 준비: stopwatch STOP + CLEAR
        set_sw(0, 1'b1); sw_stop; tap(BL);

        // ===== P1 S-01 : RUN / STOP =====
        tc_begin("P1 S-01 run/stop");
        chk(sw_run == 1'b0, "start in STOP");
        chk_t(sw_live, 24'd0, "start from 00:00:00.00");
        tap(BR); chk(sw_run == 1'b1, "STOP -R-> RUN");
        sync_sw; a = sw_live; wtick(150);
        chk_t(sw_live, add_cs(a, 150), "RUN counts up exactly 150 ticks");
        chk_t(sw_disp, sw_live, "display = live value");
        tap(BR); chk(sw_run == 1'b0, "RUN -R-> STOP");
        wclk(1); a = sw_live; wtick(100);
        chk_t(sw_live, a, "frozen in STOP");
        tc_end;

        // ===== P1 S-02 : Count Up / Down =====
        tc_begin("P1 S-02 mode");
        tap(BU); chk(sw_mode == 1'b1, "STOP: U -> Count Down"); chk(sw_run == 1'b0, "still STOP");
        tap(BR); sync_sw; a = sw_live; wtick(50);
        chk_t(sw_live, add_cs(a, -50), "Count Down decreases exactly 50 ticks");
        tap(BU); chk(sw_mode == 1'b1, "U ignored in RUN (R-11)"); chk(sw_run == 1'b1, "still RUN");
        tap(BR); tap(BU); chk(sw_mode == 1'b0, "STOP: U -> Count Up");
        tap(BR); sync_sw; a = sw_live; wtick(50);
        chk_t(sw_live, add_cs(a, 50), "Count Up increases exactly 50 ticks");
        tap(BR);
        tc_end;

        // ===== P1 S-03 : CLEAR =====
        tc_begin("P1 S-03 clear");
        chk(to_cs(sw_live) != 0, "non-zero before CLEAR");
        tap(BL);
        chk_t(sw_live, 24'd0, "STOP: L -> 00:00:00.00");
        chk_t(sw_disp, 24'd0, "display 00:00:00.00");
        chk(sw_mode == 1'b0, "mode kept");
        tap(BR); wtick(30); a = sw_live;
        tap(BL);
        chk(sw_run == 1'b1, "L ignored in RUN (R-11)");
        chk(to_cs(sw_live) > to_cs(a), "not cleared in RUN");
        tap(BR);
        tc_end;

        // ===== P1 S-04 : LAP =====
        tc_begin("P1 S-04 lap");
        e0 = lap_events; tap(BD);
        chk_i(lap_events, e0, "D ignored in STOP (R-11)");
        chk(lap_hold == 1'b0, "no hold in STOP");
        tap(BR); wtick(20);
        e0 = lap_events; tap(BD);
        chk_i(lap_events, e0 + 1, "LAP accepted in RUN");
        chk(lap_hold == 1'b1, "hold active");
        chk_t(sw_disp, lap_val, "display = captured value");
        chk(to_cs(sw_live) > to_cs(lap_val), "internal count continues");
        n = 0; r = 0;
        while (lap_hold === 1'b1 && r < 3*HOLD) begin
            @(posedge clk); #2; r = r + 1;
            if (lap_hold === 1'b1 && sw_disp !== lap_val) n = n + 1;
        end
        wclk(1);
        chk_i(n, 0, "display held during whole hold");
        chk_i(hold_fall_cyc - lap_cap_cyc, HOLD, "hold length = HOLD_COUNT clk (3 s)");
        chk_t(sw_disp, sw_live, "returns to live value after hold");
        tc_end;

        // ===== P1 C-01 : sw0 전환, 백그라운드 진행(R-07) =====
        tc_begin("P1 C-01 sw0 switch");
        chk(sw_run == 1'b1, "stopwatch RUN");
        set_sw(0, 1'b0); wclk(1); chk(led[1] == 1'b1, "sw0=0 -> led[1]=1");
        set_sw(0, 1'b1); wclk(1); chk(led[1] == 1'b0, "sw0=1 -> led[1]=0");
        sync_sw; s0 = sw_live; cs0 = cyc;
        sync_wt; t0 = wt;      cw0 = cyc;
        for (i = 0; i < 40; i = i + 1) begin
            r = {$random(seed)} % 3000 + 1;
            repeat (r) @(negedge clk);
            sw[0] = ~sw[0];
            if (i % 3 == 0) sw[1] = ~sw[1];
        end
        set_sw(0, 1'b0); set_sw(1, 1'b0);
        tap(BR); tap(BL); tap(BU); tap(BD);               // sw0=0: stopwatch에 전달되면 안 됨
        chk(sw_run == 1'b1 && sw_mode == 1'b0 && lap_hold == 1'b0, "buttons with sw0=0 do not reach stopwatch");
        sync_sw; chk_t(sw_live, add_cs(s0, (cyc - cs0) / F_CNT), "stopwatch kept running (exact)");
        sync_wt; chk_t(wt,      add_cs(t0, (cyc - cw0) / F_CNT), "watch kept running (exact)");
        tc_end;

        // ===== P1 C-02 : sw1 표시 단위, 프레임 디코드 =====
        tc_begin("P1 C-02 sw1 display");
        set_sw(0, 1'b1); sw_stop;
        sw_force(13, 45, 27, 8);
        set_sw(1, 1'b0); wclk(1); chk(led[0] == 1'b0, "sw1=0 -> led[0]=0");
        capture_frame;  chk_frame(8'h80, 8'hc0, 8'hf8, 8'ha4, 8'h7f);   // 27.08, dot on
        set_sw(1, 1'b1); wclk(1); chk(led[0] == 1'b1, "sw1=1 -> led[0]=1");
        capture_frame;  chk_frame(8'h92, 8'h99, 8'hb0, 8'hf9, 8'h7f);   // 13.45
        sw_force(13, 45, 27, 58);
        set_sw(1, 1'b0);
        capture_frame;  chk_frame(8'h80, 8'h92, 8'hf8, 8'ha4, 8'hff);   // 27.58, dot off
        tap(BR); sync_sw; a = sw_live; cs0 = cyc;
        for (i = 0; i < 10; i = i + 1) begin repeat (2000) @(negedge clk); sw[1] = ~sw[1]; end
        sync_sw; chk_t(sw_live, add_cs(a, (cyc - cs0) / F_CNT), "count unaffected by sw1");
        tap(BR); set_sw(1, 1'b0);
        tc_end;

        // ===== P3 E-02 : Watch 올림 전체 (23:59:59.xx -> 00:00:00.xx) =====
        tc_begin("P3 E-02 watch carry");
        set_sw(0, 1'b0); set_sw(2, 1'b1); wclk(2);
        wt_goto(0, 59); tap(BL); wt_goto(1, 59); tap(BL); wt_goto(2, 23);
        wclk(1); f = wt;
        chk(f[23:7] == {5'd23, 6'd59, 6'd59}, "set to 23:59:59");
        set_sw(2, 1'b0);
        sync_wt; chk_t(wt, add_cs(f, 1), "resume +1 tick");
        a = wt;
        n = (100 - a[6:0]) % 100 + 3;
        wtick(n);
        chk_t(wt, add_cs(a, n), "msec->sec->min->hour->day carry");
        chk(wt[23:7] == 17'd0, "rolled over to 00:00:00");
        tc_end;

        // ===== P3 E-03 : Stopwatch Count Up 올림 =====
        tc_begin("P3 E-03 sw up carry");
        set_sw(0, 1'b1); sw_mode_up;
        sw_force(0, 0, 59, 10);  tap(BR); sync_sw; a = sw_live; n = 100 - a[6:0] + 3; wtick(n);
        chk_t(sw_live, add_cs(a, n), "sec 59 -> min carry"); tap(BR);
        sw_force(0, 59, 59, 10); tap(BR); sync_sw; a = sw_live; n = 100 - a[6:0] + 3; wtick(n);
        chk_t(sw_live, add_cs(a, n), "min 59 -> hour carry"); tap(BR);
        sw_force(23, 59, 59, 10); tap(BR); sync_sw; a = sw_live; n = 100 - a[6:0] + 3; wtick(n);
        chk_t(sw_live, add_cs(a, n), "23:59:59.99 -> 00:00:00.00 (R-02)");
        chk(sw_live[23:7] == 17'd0, "wrapped, not stopped"); tap(BR);
        tc_end;

        // ===== P3 E-04 : Stopwatch Count Down 내림 =====
        tc_begin("P3 E-04 sw down borrow");
        tap(BU); chk(sw_mode == 1'b1, "Count Down");
        sw_force(0, 1, 0, 90); tap(BR); sync_sw; a = sw_live; n = a[6:0] + 3; wtick(n);
        chk_t(sw_live, add_cs(a, -n), "min borrow 00:01:00 -> 00:00:59"); tap(BR);
        sw_force(1, 0, 0, 90); tap(BR); sync_sw; a = sw_live; n = a[6:0] + 3; wtick(n);
        chk_t(sw_live, add_cs(a, -n), "hour borrow 01:00:00 -> 00:59:59"); tap(BR);
        tc_end;

        // ===== P3 E-05 : Count Down 언더플로 (R-03) =====
        tc_begin("P3 E-05 underflow");
        tap(BL); chk_t(sw_live, 24'd0, "cleared"); chk(sw_mode == 1'b1, "Count Down kept");
        fork
            tap(BR);
            begin
                wait (sw_run === 1'b1);
                n = 0;
                while (sw_live == 24'd0 && n < 4*F_CNT) begin @(posedge clk); #2; n = n + 1; end
                repeat (5) @(posedge clk); #2;
                chk_t(sw_live, hmsc(23,59,59,99), "00:00:00.00 -> 23:59:59.99");
            end
        join
        sync_sw; a = sw_live; wtick(10);
        chk_t(sw_live, add_cs(a, -10), "keeps counting down after underflow");
        tap(BR); tap(BU);
        tc_end;

        // ===== P3 E-06 : 디바운스 경계 (6장: <7 us 거부, >=8 us 1회) =====
        tc_begin("P3 E-06 debounce");
        set_sw(0, 1'b1); sw_stop;                         // STOP: btnD는 무시되므로 부작용 없음
        for (i = 0; i < 10; i = i + 1) begin
            p = pc[BD]; press_m(4'b1000, 3000, ({$random(seed)} % 100) * 10 + 2);
            chk_i(pc[BD] - p, 0, "3.0 us high rejected");
            p = pc[BD]; press_m(4'b1000, 6900, ({$random(seed)} % 100) * 10 + 2);
            chk_i(pc[BD] - p, 0, "6.9 us high rejected");
            p = pc[BD]; press_m(4'b1000, 8100, ({$random(seed)} % 100) * 10 + 2);
            chk_i(pc[BD] - p, 1, "8.1 us high -> 1 pulse");
            p = pc[BD]; press_m(4'b1000, 12000, ({$random(seed)} % 100) * 10 + 2);
            chk_i(pc[BD] - p, 1, "12 us high -> 1 pulse");
        end
        tc_end;

        // ===== P3 E-07 : 채터링 =====
        tc_begin("P3 E-07 chatter");
        p = pc[BD];
        @(negedge clk);
        btnD = 1; #3000; btnD = 0; #2000; btnD = 1; #5000; btnD = 0; #1500;
        btnD = 1; #30000; btnD = 0; #20000;
        chk_i(pc[BD] - p, 1, "bounces (<7 us) then 30 us high -> 1 pulse");
        p = pc[BD];
        @(negedge clk);
        btnD = 1; #10000; btnD = 0; #2000; btnD = 1; #10000; btnD = 0; #20000;
        chk_i(pc[BD] - p, 2, "two >=8 us highs split by 2 us low -> 2 pulses (6장 문구, V-03)");
        tc_end;

        // ===== P3 E-08 : 설정 중 sw0 전환 (R-08) =====
        tc_begin("P3 E-08 R-08");
        set_sw(0, 1'b0); set_sw(2, 1'b1); wclk(2);
        chk(set_field == 3'b101, "SET_SEC");
        tap(BL); chk(set_field == 3'b110, "SET_MIN");
        set_sw(0, 1'b1); wclk(1);
        chk(set_field == 3'b000 && blink_en == 1'b0, "sw0=1 -> IDLE at next clk");
        sync_wt; a = wt; wtick(50);
        chk_t(wt, add_cs(a, 50), "watch resumes while sw2 still 1");
        set_sw(0, 1'b0); wclk(1);
        chk(set_field == 3'b101 && blink_en == 1'b1, "re-entry always at SET_SEC");
        set_sw(2, 1'b0); wclk(1);
        chk(set_field == 3'b000, "IDLE");
        tc_end;

        // ===== P3 E-10 : 동시 입력 우선순위 (R-11) =====
        tc_begin("P3 E-10 R-11");
        set_sw(0, 1'b1); sw_mode_up;
        sw_force(0, 0, 10, 0);
        m0 = sw_mode;
        press_m(4'b0111, BTN_HIGH_NS, 0);                 // R+L+U
        chk(sw_run == 1'b1, "R+L+U in STOP -> RUN");
        chk(sw_mode == m0, "mode unchanged");
        chk(to_cs(sw_live) >= 1000, "not cleared");
        tap(BR);
        press_m(4'b0110, BTN_HIGH_NS, 0);                 // L+U
        chk_t(sw_live, 24'd0, "L+U in STOP -> CLEAR");
        chk(sw_mode == m0, "mode unchanged");
        chk(sw_run == 1'b0, "still STOP");
        e0 = lap_events;
        press_m(4'b1100, BTN_HIGH_NS, 0);                 // U+D
        chk(sw_mode == ~m0, "U+D in STOP -> MODE toggled");
        chk_i(lap_events, e0, "LAP ignored in STOP");
        tap(BU);
        tc_end;

        // ===== P3 E-11 : LAP 유지 중 STOP / 재입력 (R-09) =====
        tc_begin("P3 E-11 R-09");
        tap(BR); wtick(20);
        tap(BD); lv = lap_val; chk(lap_hold == 1'b1, "hold");
        tap(BR); chk(sw_run == 1'b0, "STOP during hold");
        wclk(1); frozen = sw_live;
        chk_t(sw_disp, lv, "display keeps lap value after STOP");
        wait_hold_end;
        chk_i(hold_fall_cyc - lap_cap_cyc, HOLD, "hold timer unaffected by STOP");
        chk_t(sw_disp, frozen, "after hold -> stopped value");
        chk_t(sw_live, frozen, "stopped value unchanged");
        tap(BR); wtick(20);
        tap(BD); cap1 = lap_cap_cyc; f1 = hold_fall_cyc;
        wclk(10000);
        tap(BD); lv2 = lap_val; cap2 = lap_cap_cyc;
        chk(cap2 > cap1, "second LAP accepted during hold");
        chk_i(hold_fall_cyc, f1, "hold not released between LAPs");
        chk_t(sw_disp, lv2, "display = second lap value");
        wait_hold_end;
        chk_i(hold_fall_cyc - cap2, HOLD, "3 s restarted from second LAP");
        tap(BR);
        tc_end;

        // ===== P3 E-12 : LAP 유지 중 CLEAR (R-15) =====
        tc_begin("P3 E-12 R-15");
        m0 = sw_mode;
        tap(BR); wtick(20);
        tap(BD); lv = lap_val;
        tap(BR); tap(BL);
        chk_t(sw_live, 24'd0, "CLEAR -> internal 00:00:00.00");
        chk(lap_hold == 1'b1, "hold still active");
        chk_t(sw_disp, lv, "display keeps lap value until hold ends");
        wait_hold_end;
        chk_t(sw_disp, 24'd0, "after hold -> 00:00:00.00");
        chk(sw_mode == m0, "mode unchanged by CLEAR");
        tc_end;

        mon_en = 1'b0;
        $display("SUMMARY tb_eval_func : pass=%0d fail=%0d (C-03 = C-03a and C-03b)", n_pass, n_fail);
        $finish;
    end

endmodule