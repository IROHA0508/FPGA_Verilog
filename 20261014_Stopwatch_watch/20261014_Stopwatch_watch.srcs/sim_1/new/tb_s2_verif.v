`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// tb_s2_verif : 2차 세션 3단계 성능 검증용 테스트벤치 (평가 에이전트 작성)
//
//  TEST_MODE = 0 : V1(11개 TC) + V3(엣지 케이스) 방향성 테스트
//  TEST_MODE = 1 : V4 장시간·랜덤 스트레스 (STRESS_HOURS 시간, 1시간마다 체크포인트)
//
//  축소 비율 1/10,000 (사용자 확정값)
//    F_COUNT    1,000,000   -> 100     (10 ms 틱 = 1 us)
//    HOLD_COUNT 300,000,000 -> 30,000  (LAP 3 s = 300 us)
//    HALF_COUNT 25,000,000  -> 2,500   (깜빡임 0.25 s = 25 us)
//  축소하지 않는 값: 디바운스(1 MHz 샘플, 8 us), FND 스캔(62,500 카운트 토글)
//
//  자동 체커 (두 모드 공통, 매 클럭 동작)
//    SB-1 기준 모델 비교 : 명세로 만든 Watch/Stopwatch 모델과 DUT 시간값(Watch, Stopwatch
//                          실시간 카운터, Stopwatch 표시값) 비교. 이벤트 직후 G클럭은 비교 보류
//    SB-2 틱 주기       : 실행 중 누적 클럭이 정확히 F_COUNT일 때만 10 ms 틱이 나와야 함
//                          (정지 중 틱 발생, 정지/재개 시 위상 손실도 검출)
//    SB-3 값 범위       : msec<100, sec<60, min<60, hour<24 (매 클럭, 보류 없음)
//    SB-4 FND 출력      : 모델로 계산한 fnd_com/fnd_font와 비교 (997클럭마다 표본)
//    SB-5 FND 스캔      : ds_sel이 125,000클럭마다 +1, fnd_com은 한 비트만 0
//    SB-6 LED           : led[1]==~sw[0] (매 클럭), led[0]==표시 단위 (보류 구간 제외)
//    SB-7 디바운스      : 1클럭 펄스 폭, 자극별 기대 펄스 수 (7us 미만 0회, 8us 이상 1회)
//    SB-8 LAP 캡처      : 캡처값 == 모델 실시간값. 캐리 전파 도중(틱 후 5클럭 이내) 캡처로
//                          부분값이 잡히면 WARN(RIPPLE)으로 따로 집계
//
//  관측용 내부 신호 (화이트박스): 디바운스 출력 w_btn, 10 ms 틱, FND ds_sel, LAP 레지스터
//  명세 공백 항목은 제출 RTL 동작을 기준으로 모델링함 (사용자 확정 사항)
//////////////////////////////////////////////////////////////////////////////////
module tb_s2_verif;

    parameter TEST_MODE    = 1;
    parameter STRESS_HOURS = 6;
    parameter SEED         = 20261024;

    localparam F_COUNT    = 100;
    localparam HOLD_COUNT = 30000;
    localparam HALF_COUNT = 2500;
    localparam SCAN_STEP  = 125000;                 // ds_sel 한 칸 (클럭)
    localparam G          = 8;                      // 비교 보류 구간 (클럭)
    localparam [63:0] CYC_PER_HOUR = 64'd36000000;  // 축소 1시간 = 100 tick/s * 3600 s * F_COUNT

    localparam W_IDLE = 2'd0, W_SEC = 2'd1, W_MIN = 2'd2, W_HOUR = 2'd3;
    localparam S_STOP = 1'b0, S_RUN = 1'b1;

    // ------------------------------------------------------------------ DUT
    reg        clk = 1'b0;
    reg        rst = 1'b1;
    reg  [3:0] bt  = 4'b0000;           // {D, U, L, R}
    reg  [2:0] sw  = 3'b000;
    wire [3:0] fnd_com;
    wire [7:0] fnd_font;
    wire [1:0] led;

    stopwatch_watch_integrate dut (
        .clk(clk), .rst(rst),
        .btnR(bt[0]), .btnL(bt[1]), .btnU(bt[2]), .btnD(bt[3]),
        .sw(sw), .fnd_com(fnd_com), .fnd_font(fnd_font), .led(led)
    );

    defparam dut.U_WATCH.U_WATCH_DATATPATH.U_TICK_GEN_100HMZ.F_COUNT         = F_COUNT;
    defparam dut.U_STOPWATCH.U_STOPWATCH_DATATPATH.U_TICK_GEN_100HMZ.F_COUNT = F_COUNT;
    defparam dut.U_STOPWATCH.U_LAP_MODULE.HOLD_COUNT                         = HOLD_COUNT;
    defparam dut.U_FND_CNTL.U_BLINK.HALF_COUNT                               = HALF_COUNT;

    always #5 clk = ~clk;   // 100 MHz

    // ------------------------------------------------------------------ 관측 신호
    wire [3:0]  p_db      = dut.U_BTN_DEBOUNCE.w_btn;
    wire        p_wt_tick = dut.U_WATCH.U_WATCH_DATATPATH.w_tick_10ms;
    wire        p_sw_tick = dut.U_STOPWATCH.U_STOPWATCH_DATATPATH.w_tick_10ms;
    wire [23:0] p_wt      = dut.w_wt_time;
    wire [23:0] p_sw      = dut.w_sw_time;
    wire [23:0] p_live    = {dut.U_STOPWATCH.w_live_hour, dut.U_STOPWATCH.w_live_min,
                             dut.U_STOPWATCH.w_live_sec,  dut.U_STOPWATCH.w_live_msec};
    wire [23:0] p_lap     = {dut.U_STOPWATCH.U_LAP_MODULE.lap_hour, dut.U_STOPWATCH.U_LAP_MODULE.lap_min,
                             dut.U_STOPWATCH.U_LAP_MODULE.lap_sec,  dut.U_STOPWATCH.U_LAP_MODULE.lap_msec};
    wire [2:0]  p_ds      = dut.U_FND_CNTL.w_ds_sel;

    // ------------------------------------------------------------------ 시간 함수
    function [23:0] pack; input integer h, m, s, c;
        pack = {h[4:0], m[5:0], s[5:0], c[6:0]};
    endfunction
    function integer f_h; input [23:0] t; f_h = t[23:19]; endfunction
    function integer f_m; input [23:0] t; f_m = t[18:13]; endfunction
    function integer f_s; input [23:0] t; f_s = t[12:7];  endfunction
    function integer f_c; input [23:0] t; f_c = t[6:0];   endfunction
    function integer to_cs; input [23:0] t;
        to_cs = ((f_h(t) * 60 + f_m(t)) * 60 + f_s(t)) * 100 + f_c(t);
    endfunction

    function [23:0] t_inc; input [23:0] t;
        integer h, m, s, c;
        begin
            h = f_h(t); m = f_m(t); s = f_s(t); c = f_c(t);
            if (c == 99) begin
                c = 0;
                if (s == 59) begin
                    s = 0;
                    if (m == 59) begin m = 0; h = (h == 23) ? 0 : h + 1; end
                    else m = m + 1;
                end else s = s + 1;
            end else c = c + 1;
            t_inc = pack(h, m, s, c);
        end
    endfunction

    function [23:0] t_dec; input [23:0] t;
        integer h, m, s, c;
        begin
            h = f_h(t); m = f_m(t); s = f_s(t); c = f_c(t);
            if (c == 0) begin
                c = 99;
                if (s == 0) begin
                    s = 59;
                    if (m == 0) begin m = 59; h = (h == 0) ? 23 : h - 1; end
                    else m = m - 1;
                end else s = s - 1;
            end else c = c - 1;
            t_dec = pack(h, m, s, c);
        end
    endfunction

    // 설정 모드 +1/-1 : 선택 필드만 순환, 상위 자리 전파 없음 (W-01, W-02, R-05)
    function [23:0] t_field; input [23:0] t; input [1:0] fld; input up;
        integer h, m, s, c;
        begin
            h = f_h(t); m = f_m(t); s = f_s(t); c = f_c(t);
            case (fld)
                W_SEC : s = up ? ((s == 59) ? 0 : s + 1) : ((s == 0) ? 59 : s - 1);
                W_MIN : m = up ? ((m == 59) ? 0 : m + 1) : ((m == 0) ? 59 : m - 1);
                W_HOUR: h = up ? ((h == 23) ? 0 : h + 1) : ((h == 0) ? 23 : h - 1);
                default: ;
            endcase
            t_field = pack(h, m, s, c);
        end
    endfunction

    function [7:0] font; input [3:0] code;   // 01 문서 5-4 fnd_font 표
        case (code)
            4'd0: font = 8'hC0; 4'd1: font = 8'hF9; 4'd2: font = 8'hA4; 4'd3: font = 8'hB0;
            4'd4: font = 8'h99; 4'd5: font = 8'h92; 4'd6: font = 8'h82; 4'd7: font = 8'hF8;
            4'd8: font = 8'h80; 4'd9: font = 8'h90; 4'hE: font = 8'h7F; default: font = 8'hFF;
        endcase
    endfunction

    function [3:0] com_of; input [1:0] d;
        case (d) 2'd0: com_of = 4'b1110; 2'd1: com_of = 4'b1101; 2'd2: com_of = 4'b1011; default: com_of = 4'b0111; endcase
    endfunction

    task show; input [23:0] t;
        $write("%02d:%02d:%02d.%02d", f_h(t), f_m(t), f_s(t), f_c(t));
    endtask

    // ------------------------------------------------------------------ 기준 모델 상태
    reg  [63:0] cyc;
    reg  [1:0]  m_ws;           // Watch 설정 FSM (명세 W-03, R-08, R-10)
    reg  [23:0] m_wt;
    reg         m_ss;           // Stopwatch STOP/RUN
    reg         m_mode;         // 0 up, 1 down
    reg  [23:0] m_live, m_lap;
    reg         m_hold;
    integer     m_hold_cnt;
    reg         m_blink_on;
    integer     m_blink_cnt;
    integer     wt_acc, sw_acc;  // 실행 클럭 누적 (SB-2)
    integer     quiet;
    reg  [2:0]  sw_q;
    reg         lap_chk;
    reg  [63:0] last_sw_tick;

    // 통계
    reg [63:0] n_cmp;
    integer sb_err, sb_warn, n_fnd, n_wt_tick, n_sw_tick, n_lap, n_set_entry;
    integer e_wt, e_sw, e_rate, e_rng, e_fnd, e_scan, e_led, e_db, e_lap;
    integer pcnt0, pcnt1, pcnt2, pcnt3;
    reg [63:0] last_pulse [0:3];
    reg [3:0]  db_q;
    integer    n_scan;
    reg [63:0] ds_last_chg;
    reg [2:0]  ds_q;
    integer    fnd_div;

    // 모델 갱신 (posedge, DUT와 같은 엣지에서 엣지 직전 값 사용)
    reg [3:0] wb, sb;
    reg       set_en;
    reg [1:0] ws_pre;
    reg       ss_pre;
    reg       evt;

    always @(posedge clk) begin
        if (rst) begin
            cyc = 0;
            m_ws = W_IDLE; m_wt = pack(12, 0, 0, 0);
            m_ss = S_STOP; m_mode = 1'b0; m_live = 0; m_lap = 0; m_hold = 1'b0; m_hold_cnt = 0;
            m_blink_on = 1'b1; m_blink_cnt = 0;
            wt_acc = 0; sw_acc = 0; quiet = 0; sw_q = sw; lap_chk = 1'b0; last_sw_tick = 0;
        end else begin
            cyc = cyc + 1;
            evt = 1'b0;
            wb = p_db & {4{~sw[0]}};
            sb = p_db & {4{ sw[0]}};
            set_en = ~sw[0] & sw[2];
            ws_pre = m_ws;
            ss_pre = m_ss;
            if (p_db != 4'b0000) evt = 1'b1;
            if (sw != sw_q) begin evt = 1'b1; sw_q = sw; end

            // ---- 깜빡임 (R-06): 설정 상태에서만 HALF_COUNT마다 반전, 진입 시 점등
            if (ws_pre == W_IDLE) begin
                m_blink_on = 1'b1; m_blink_cnt = 0;
            end else if (m_blink_cnt == HALF_COUNT - 1) begin
                m_blink_cnt = 0; m_blink_on = ~m_blink_on; evt = 1'b1;
            end else m_blink_cnt = m_blink_cnt + 1;

            // ---- Watch FSM (sw[2]/sw[0] 우선, 동시 버튼은 코드 순서 U>D>L>R)
            case (ws_pre)
                W_IDLE: if (set_en) begin m_ws = W_SEC; n_set_entry = n_set_entry + 1; end
                default: begin
                    if (!set_en) m_ws = W_IDLE;
                    else if (wb[2]) m_wt = t_field(m_wt, ws_pre, 1'b1);
                    else if (wb[3]) m_wt = t_field(m_wt, ws_pre, 1'b0);
                    else if (wb[1]) m_ws = (ws_pre == W_SEC) ? W_MIN : (ws_pre == W_MIN) ? W_HOUR : W_SEC;
                    else if (wb[0]) m_ws = (ws_pre == W_SEC) ? W_HOUR : (ws_pre == W_HOUR) ? W_MIN : W_SEC;
                end
            endcase
            if (m_ws != ws_pre) evt = 1'b1;

            // ---- Watch 틱 (SB-2)
            if (p_wt_tick) begin
                n_wt_tick = n_wt_tick + 1;
                if (wt_acc != F_COUNT) begin
                    e_rate = e_rate + 1; sb_err = sb_err + 1;
                    if (sb_err <= 60) $display("[ERR][RATE] cyc=%0d watch tick after %0d running clocks (expect %0d)", cyc, wt_acc, F_COUNT);
                end
                wt_acc = 0;
                m_wt = t_inc(m_wt);
                evt = 1'b1;
            end
            if (ws_pre == W_IDLE) wt_acc = wt_acc + 1;

            // ---- Stopwatch LAP (S-04, R-09): RUN 상태에서만 수락, 엣지 직전 실시간값 캡처
            if (sb[3] && ss_pre == S_RUN) begin
                m_lap = m_live; m_hold = 1'b1; m_hold_cnt = 0; lap_chk = 1'b1; n_lap = n_lap + 1; evt = 1'b1;
            end else if (m_hold) begin
                if (m_hold_cnt == HOLD_COUNT - 1) begin m_hold = 1'b0; m_hold_cnt = 0; evt = 1'b1; end
                else m_hold_cnt = m_hold_cnt + 1;
            end

            // ---- Stopwatch FSM (S-01~S-03, R-11: STOP에서 R > L > U)
            if (ss_pre == S_STOP) begin
                if (sb[0]) m_ss = S_RUN;
                else if (sb[1]) begin m_live = 0; sw_acc = 0; evt = 1'b1; end
                else if (sb[2]) begin m_mode = ~m_mode; evt = 1'b1; end
            end else if (sb[0]) m_ss = S_STOP;
            if (m_ss != ss_pre) evt = 1'b1;

            // ---- Stopwatch 틱 (SB-2)
            if (p_sw_tick) begin
                n_sw_tick = n_sw_tick + 1;
                if (sw_acc != F_COUNT) begin
                    e_rate = e_rate + 1; sb_err = sb_err + 1;
                    if (sb_err <= 60) $display("[ERR][RATE] cyc=%0d stopwatch tick after %0d running clocks (expect %0d)", cyc, sw_acc, F_COUNT);
                end
                sw_acc = 0;
                m_live = m_mode ? t_dec(m_live) : t_inc(m_live);
                last_sw_tick = cyc;
                evt = 1'b1;
            end
            if (ss_pre == S_RUN) sw_acc = sw_acc + 1;

            if (evt) quiet = 0; else if (quiet < 1000000) quiet = quiet + 1;
        end
    end

    // ------------------------------------------------------------------ 체커 (negedge)
    wire pred_quiet = !((m_ws == W_IDLE) && (wt_acc >= F_COUNT - G)) &&
                      !((m_ss == S_RUN)  && (sw_acc >= F_COUNT - G)) &&
                      !(m_hold && (m_hold_cnt >= HOLD_COUNT - G)) &&
                      !((m_ws != W_IDLE) && (m_blink_cnt >= HALF_COUNT - G));
    wire [23:0] m_sw_disp = m_hold ? m_lap : m_live;
    wire        exp_sel   = (m_ws != W_IDLE) ? (m_ws != W_SEC) : sw[1];

    reg  [23:0] src;
    reg  [3:0]  code;
    reg         hide_s, hide_m, hide_h, blink_off, dot_on;
    integer     i;

    always @(negedge clk) begin
        if (!rst && cyc > 2) begin
            // SB-3 값 범위
            if (f_c(p_wt) > 99 || f_s(p_wt) > 59 || f_m(p_wt) > 59 || f_h(p_wt) > 23 ||
                f_c(p_live) > 99 || f_s(p_live) > 59 || f_m(p_live) > 59 || f_h(p_live) > 23) begin
                e_rng = e_rng + 1; sb_err = sb_err + 1;
                if (sb_err <= 60) $display("[ERR][RANGE] cyc=%0d out-of-range value", cyc);
            end
            // SB-6 led[1]
            if (sw == sw_q && led[1] !== ~sw[0]) begin
                e_led = e_led + 1; sb_err = sb_err + 1;
                if (sb_err <= 60) $display("[ERR][LED1] cyc=%0d led[1]=%b sw0=%b", cyc, led[1], sw[0]);
            end
            // SB-5 fnd_com 한 비트만 0, ds_sel과 일치
            if (fnd_com !== com_of(p_ds[1:0])) begin
                e_scan = e_scan + 1; sb_err = sb_err + 1;
                if (sb_err <= 60) $display("[ERR][SCAN] cyc=%0d fnd_com=%b ds_sel=%0d", cyc, fnd_com, p_ds);
            end
            // SB-5 스캔 주기
            if (p_ds !== ds_q) begin
                if (n_scan > 0 && (cyc - ds_last_chg) != SCAN_STEP) begin
                    e_scan = e_scan + 1; sb_err = sb_err + 1;
                    if (sb_err <= 60) $display("[ERR][SCAN] cyc=%0d ds_sel step %0d clocks (expect %0d)", cyc, cyc - ds_last_chg, SCAN_STEP);
                end
                if (n_scan > 0 && p_ds !== ds_q + 3'd1) begin
                    e_scan = e_scan + 1; sb_err = sb_err + 1;
                    if (sb_err <= 60) $display("[ERR][SCAN] cyc=%0d ds_sel %0d -> %0d", cyc, ds_q, p_ds);
                end
                n_scan = n_scan + 1; ds_last_chg = cyc; ds_q = p_ds;
            end
            // SB-7 펄스 폭 / 개수
            for (i = 0; i < 4; i = i + 1) begin
                if (p_db[i]) begin
                    if (db_q[i]) begin
                        e_db = e_db + 1; sb_err = sb_err + 1;
                        if (sb_err <= 60) $display("[ERR][DEBOUNCE] cyc=%0d btn%0d pulse wider than 1 clock", cyc, i);
                    end
                    last_pulse[i] = cyc;
                end
            end
            if (p_db[0] && !db_q[0]) pcnt0 = pcnt0 + 1;
            if (p_db[1] && !db_q[1]) pcnt1 = pcnt1 + 1;
            if (p_db[2] && !db_q[2]) pcnt2 = pcnt2 + 1;
            if (p_db[3] && !db_q[3]) pcnt3 = pcnt3 + 1;
            db_q = p_db;

            // SB-8 LAP 캡처값
            if (lap_chk) begin
                lap_chk = 1'b0;
                if (p_lap !== m_lap) begin
                    if (cyc - last_sw_tick <= 5) begin
                        sb_warn = sb_warn + 1;
                        $write("[WARN][RIPPLE] cyc=%0d LAP captured partial carry value ", cyc); show(p_lap);
                        $write(" (model "); show(m_lap); $display(")");
                    end else begin
                        e_lap = e_lap + 1; sb_err = sb_err + 1;
                        if (sb_err <= 60) begin
                            $write("[ERR][LAP] cyc=%0d captured ", cyc); show(p_lap); $write(" expect "); show(m_lap); $display("");
                        end
                    end
                    m_lap = p_lap;   // 이후 비교를 위해 동기화
                end
            end

            // SB-1 / SB-6 기준 모델 비교 (보류 구간 제외)
            if (quiet >= G && pred_quiet && sw == sw_q) begin
                n_cmp = n_cmp + 1;
                if (p_wt !== m_wt) begin
                    e_wt = e_wt + 1; sb_err = sb_err + 1;
                    if (sb_err <= 60) begin $write("[ERR][WATCH] cyc=%0d dut ", cyc); show(p_wt); $write(" model "); show(m_wt); $display(""); end
                    m_wt = p_wt;
                end
                if (p_live !== m_live) begin
                    e_sw = e_sw + 1; sb_err = sb_err + 1;
                    if (sb_err <= 60) begin $write("[ERR][SW_LIVE] cyc=%0d dut ", cyc); show(p_live); $write(" model "); show(m_live); $display(""); end
                    m_live = p_live;
                end
                if (p_sw !== m_sw_disp) begin
                    e_sw = e_sw + 1; sb_err = sb_err + 1;
                    if (sb_err <= 60) begin $write("[ERR][SW_DISP] cyc=%0d dut ", cyc); show(p_sw); $write(" model "); show(m_sw_disp); $display(" hold=%0d", m_hold); end
                end
                if (led[0] !== exp_sel) begin
                    e_led = e_led + 1; sb_err = sb_err + 1;
                    if (sb_err <= 60) $display("[ERR][LED0] cyc=%0d led[0]=%b expect %b", cyc, led[0], exp_sel);
                end

                // SB-4 FND 표본
                fnd_div = fnd_div + 1;
                if (fnd_div >= 997) begin
                    fnd_div = 0;
                    n_fnd = n_fnd + 1;
                    src       = sw[0] ? m_sw_disp : m_wt;
                    blink_off = (m_ws != W_IDLE) & ~m_blink_on;
                    hide_s    = blink_off & (m_ws == W_SEC);
                    hide_m    = blink_off & (m_ws == W_MIN);
                    hide_h    = blink_off & (m_ws == W_HOUR);
                    dot_on    = (m_ws != W_IDLE) | (f_c(src) < 50);      // R-14a
                    case (p_ds)
                        3'd0: code = exp_sel ? (hide_m ? 4'hF : f_m(src) % 10) : (f_c(src) % 10);
                        3'd1: code = exp_sel ? (hide_m ? 4'hF : f_m(src) / 10) : (f_c(src) / 10);
                        3'd2: code = exp_sel ? (hide_h ? 4'hF : f_h(src) % 10) : (hide_s ? 4'hF : f_s(src) % 10);
                        3'd3: code = exp_sel ? (hide_h ? 4'hF : f_h(src) / 10) : (hide_s ? 4'hF : f_s(src) / 10);
                        3'd6: code = dot_on ? 4'hE : 4'hF;
                        default: code = 4'hF;
                    endcase
                    if (fnd_font !== font(code)) begin
                        e_fnd = e_fnd + 1; sb_err = sb_err + 1;
                        if (sb_err <= 60) $display("[ERR][FND] cyc=%0d ds_sel=%0d fnd_font=%h expect %h (sw=%b ws=%0d)", cyc, p_ds, fnd_font, font(code), sw, m_ws);
                    end
                end
            end
        end
    end

    // ------------------------------------------------------------------ 자극 태스크
    task wait_cyc; input integer n; begin repeat (n) @(negedge clk); end endtask
    task wait_until; input [63:0] t; begin while (cyc < t) @(negedge clk); end endtask

    // 버튼 누름 : mask 비트 = {D,U,L,R}, hi 클럭 동안 high, 이후 1,500클럭(15 us) low
    task press; input [3:0] mask; input integer hi;
        begin
            @(negedge clk); bt = bt | mask;
            repeat (hi) @(negedge clk);
            bt = bt & ~mask;
            repeat (1500) @(negedge clk);
        end
    endtask
    task tap; input [3:0] mask; begin press(mask, 1000); end endtask   // 10 us 누름

    // 채터링 : high 300, low 150, high 500, low 200, high last_hi
    task bounce; input [3:0] mask; input integer last_hi;
        begin
            @(negedge clk);
            bt = bt | mask;  repeat (300) @(negedge clk);
            bt = bt & ~mask; repeat (150) @(negedge clk);
            bt = bt | mask;  repeat (500) @(negedge clk);
            bt = bt & ~mask; repeat (200) @(negedge clk);
            bt = bt | mask;  repeat (last_hi) @(negedge clk);
            bt = bt & ~mask; repeat (1500) @(negedge clk);
        end
    endtask

    task set_sw; input [2:0] v; begin @(negedge clk); sw = v; wait_cyc(20); end endtask

    // ------------------------------------------------------------------ TC 관리
    reg [8*48:1] tc_name [0:63];
    reg          tc_res  [0:63];
    integer      tc_n, tc_fail, tc_err0, n_tc_fail;
    reg [8*48:1] cur;

    task tc_begin; input [8*48:1] name;
        begin cur = name; tc_fail = 0; tc_err0 = sb_err; $display("\n---- %0s (cyc=%0d)", name, cyc); end
    endtask
    task tc_end;
        begin
            tc_name[tc_n] = cur;
            tc_res[tc_n]  = (tc_fail == 0) && (sb_err == tc_err0);
            $display("[TC] %0s : %0s  (explicit_fail=%0d, scoreboard_err=%0d)", cur,
                     tc_res[tc_n] ? "PASS" : "FAIL", tc_fail, sb_err - tc_err0);
            tc_n = tc_n + 1;
        end
    endtask
    task chk; input cond; input [8*72:1] msg;
        begin
            if (cond) $display("  [ok]   %0s", msg);
            else begin tc_fail = tc_fail + 1; $display("  [FAIL] %0s  (cyc=%0d)", msg, cyc); end
        end
    endtask

    // 설정 모드에서 U를 눌러 어느 필드가 +1 되는지 확인 후 D로 원복 (W-03 블랙박스 확인)
    reg [23:0] pb0, pb1;
    task probe_field; input [1:0] fld; input [8*72:1] msg;
        begin
            pb0 = p_wt; tap(4'b0100); pb1 = p_wt;
            chk(pb1 == t_field(pb0, fld, 1'b1), msg);
            tap(4'b1000);
            chk(p_wt == pb0, "  restore with btnD");
        end
    endtask

    // 정지된 표시 4자리 읽기 (fnd_com[3]..[0] 순서), 소수점 칸(ds_sel=6) 포함
    reg [7:0] rd [0:3];
    reg [7:0] rd_dot;
    reg [7:0] seen;
    integer   k;
    task read_display;
        begin
            seen = 8'h00;
            while (seen != 8'hFF) begin
                @(negedge clk);
                if (!seen[p_ds]) begin
                    wait_cyc(500);  // 칸 중간에서 읽기
                    if (p_ds < 4) rd[p_ds] = fnd_font;
                    if (p_ds == 6) rd_dot = fnd_font;
                    seen[p_ds] = 1'b1;
                end
            end
        end
    endtask

    integer pc_b [0:3];
    task snap_pc; begin pc_b[0] = pcnt0; pc_b[1] = pcnt1; pc_b[2] = pcnt2; pc_b[3] = pcnt3; end endtask
    function integer pc_delta; input integer b;
        case (b) 0: pc_delta = pcnt0 - pc_b[0]; 1: pc_delta = pcnt1 - pc_b[1];
                 2: pc_delta = pcnt2 - pc_b[2]; default: pc_delta = pcnt3 - pc_b[3]; endcase
    endfunction
    function integer pc_total;
        input dummy; pc_total = (pcnt0 - pc_b[0]) + (pcnt1 - pc_b[1]) + (pcnt2 - pc_b[2]) + (pcnt3 - pc_b[3]);
    endfunction

    // ------------------------------------------------------------------ 방향성 테스트 (V1, V3)
    reg  [23:0] t0, t1, t2, tA, tB, tC, tS, prev;
    integer     n, b, ph, okc, s0, cnt, j;
    reg  [63:0] pA, pB, pC, tE;
    reg         seen_pre, ok;

    task run_directed;
        begin
            // ===== CK-03 리셋 직후 상태 =====
            tc_begin("TC00 reset state (R-04)");
            chk(p_wt == pack(12,0,0,0), "watch = 12:00:00.00 right after reset");
            chk(p_sw == 0 && p_live == 0, "stopwatch = 00:00:00.00");
            wait_cyc(2000);
            chk(p_live == 0, "stopwatch stays 0 (STOP) without input");
            chk(f_c(p_wt) >= 19 && f_c(p_wt) <= 21 && p_wt[23:7] == pack(12,0,0,0) >> 7, "watch runs immediately (~20 ticks after 2000 clk)");
            chk(led == 2'b10, "led[1]=1 (watch), led[0]=0 (sec/msec)");
            tc_end;

            // ===== W-01, W-02 =====
            tc_begin("TC-W02/W01 set inc/dec wrap (R-05)");
            set_sw(3'b010);                      // sw1=1 상태에서 진입 -> 설정 표시 우선 확인
            set_sw(3'b110);
            chk(led[0] == 1'b0, "SET_SEC shows Sec/Msec even with sw1=1 (CK-15)");
            t0 = p_wt; wait_cyc(5000);
            chk(p_wt == t0, "time frozen in set mode (C-03)");
            s0 = f_s(p_wt);
            for (n = 0; n < s0; n = n + 1) tap(4'b1000);
            chk(f_s(p_wt) == 0, "SEC: btnD down to 00");
            tap(4'b1000);
            chk(p_wt == pack(f_h(t0), f_m(t0), 59, f_c(t0)), "SEC: btnD 00 -> 59, min/hour/msec unchanged");
            tap(4'b0100);
            chk(p_wt == pack(f_h(t0), f_m(t0), 0, f_c(t0)),  "SEC: btnU 59 -> 00, min unchanged");
            tap(4'b0010);                         // L : SEC -> MIN
            chk(led[0] == 1'b1, "SET_MIN shows Hour/Min (CK-15)");
            s0 = f_m(p_wt);
            for (n = 0; n < s0; n = n + 1) tap(4'b1000);
            tap(4'b1000);
            chk(p_wt == pack(f_h(t0), 59, 0, f_c(t0)), "MIN: btnD 00 -> 59, hour unchanged");
            tap(4'b0100);
            chk(p_wt == pack(f_h(t0), 0, 0, f_c(t0)),  "MIN: btnU 59 -> 00, hour unchanged");
            tap(4'b0010);                         // L : MIN -> HOUR
            s0 = f_h(p_wt);
            for (n = 0; n < s0; n = n + 1) tap(4'b1000);
            chk(f_h(p_wt) == 0, "HOUR: btnD down to 00");
            tap(4'b1000);
            chk(p_wt == pack(23, 0, 0, f_c(t0)), "HOUR: btnD 00 -> 23");
            tap(4'b0100);
            chk(p_wt == pack(0, 0, 0, f_c(t0)),  "HOUR: btnU 23 -> 00");
            tc_end;

            // ===== W-03 =====  (현재 HOUR)
            tc_begin("TC-W03 field move L/R");
            tap(4'b0010); probe_field(W_SEC,  "L: HOUR -> SEC");
            tap(4'b0010); probe_field(W_MIN,  "L: SEC  -> MIN");
            tap(4'b0010); probe_field(W_HOUR, "L: MIN  -> HOUR");
            tap(4'b0001); probe_field(W_MIN,  "R: HOUR -> MIN");
            tap(4'b0001); probe_field(W_SEC,  "R: MIN  -> SEC");
            tap(4'b0001); probe_field(W_HOUR, "R: SEC  -> HOUR");
            tc_end;

            // ===== W-04 =====  (현재 HOUR = 00)
            tc_begin("TC-W04 long press = 1 count");
            t0 = p_wt; press(4'b0100, 300000);   // 3 ms 누름
            chk(p_wt == t_field(t0, W_HOUR, 1'b1), "btnU held 3 ms -> +1 only");
            t0 = p_wt; press(4'b1000, 300000);
            chk(p_wt == t_field(t0, W_HOUR, 1'b0), "btnD held 3 ms -> -1 only");
            tc_end;

            // ===== 23:59:59 설정 후 C-03 해제, E-01 캐리 =====
            tc_begin("TC-C03 set exit + V3 watch 23:59:59.99 wrap");
            tap(4'b1000);                         // HOUR 00 -> 23
            tap(4'b0010); tap(4'b1000);           // SEC 00 -> 59
            tap(4'b0010); tap(4'b1000);           // MIN 00 -> 59
            t1 = p_wt;
            chk(t1 == pack(23, 59, 59, f_c(t0)), "set to 23:59:59 (msec kept)");
            set_sw(3'b010);                       // sw2=0 -> IDLE
            chk(f_c(p_wt) <= f_c(t1) + 1, "msec not reset to 0 on exit (R-05)");
            seen_pre = 1'b0; ok = 1'b0;
            for (n = 0; n < 20000 && !ok; n = n + 1) begin
                @(negedge clk);
                if (p_wt == pack(23,59,59,99)) seen_pre = 1'b1;
                if (f_h(p_wt) == 0) ok = 1'b1;
            end
            wait_cyc(6);
            chk(seen_pre, "watch reached 23:59:59.99");
            chk(ok && p_wt == pack(0,0,0,0), "23:59:59.99 -> 00:00:00.00 (R-04)");
            chk(led[0] == 1'b1, "IDLE + sw1=1 -> led[0]=1 (C-02)");
            set_sw(3'b000);
            chk(led[0] == 1'b0, "IDLE + sw1=0 -> led[0]=0 (C-02)");
            tc_end;

            // ===== V3 디바운스 =====
            tc_begin("TC-E05 debounce 7us/8us (CK-01)");
            okc = 0; cnt = 0;
            for (b = 0; b < 4; b = b + 1) begin
                for (ph = 0; ph < 10; ph = ph + 1) begin
                    wait_cyc(ph * 10 + 7);
                    snap_pc; press(4'b0001 << b, 600);        cnt = cnt + 1; if (pc_total(0) == 0) okc = okc + 1; else $display("  [FAIL] btn%0d 6.0us high -> %0d pulse", b, pc_total(0));
                    snap_pc; press(4'b0001 << b, 690);        cnt = cnt + 1; if (pc_total(0) == 0) okc = okc + 1; else $display("  [FAIL] btn%0d 6.9us high -> %0d pulse", b, pc_total(0));
                    snap_pc; bounce(4'b0001 << b, 650);       cnt = cnt + 1; if (pc_total(0) == 0) okc = okc + 1; else $display("  [FAIL] btn%0d bounce(max 6.5us) -> %0d pulse", b, pc_total(0));
                    snap_pc; press(4'b0001 << b, 810);        cnt = cnt + 1; if (pc_total(0) == 1 && pc_delta(b) == 1) okc = okc + 1; else $display("  [FAIL] btn%0d 8.1us high -> %0d pulse", b, pc_total(0));
                    snap_pc; press(4'b0001 << b, 900);        cnt = cnt + 1; if (pc_total(0) == 1 && pc_delta(b) == 1) okc = okc + 1; else $display("  [FAIL] btn%0d 9.0us high -> %0d pulse", b, pc_total(0));
                    snap_pc; bounce(4'b0001 << b, 2000);      cnt = cnt + 1; if (pc_total(0) == 1 && pc_delta(b) == 1) okc = okc + 1; else $display("  [FAIL] btn%0d bounce + 20us stable -> %0d pulse", b, pc_total(0));
                end
                // 3 ms 누름 + 떼는 순간 채터링
                snap_pc;
                @(negedge clk); bt[b] = 1'b1; wait_cyc(300000);
                bt[b] = 1'b0; wait_cyc(80); bt[b] = 1'b1; wait_cyc(400); bt[b] = 1'b0; wait_cyc(1500);
                cnt = cnt + 1; if (pc_total(0) == 1) okc = okc + 1; else $display("  [FAIL] btn%0d 3ms + release bounce -> %0d pulse", b, pc_total(0));
            end
            $display("  debounce stimuli %0d, correct %0d", cnt, okc);
            chk(okc == cnt, "all debounce stimuli give expected pulse count");
            tc_end;

            // ===== Stopwatch =====
            set_sw(3'b001);
            tc_begin("TC-S01 run/stop");
            chk(led[1] == 1'b0, "sw0=1 -> led[1]=0");
            tap(4'b0001); wait_cyc(20000);
            t1 = p_sw; n = (cyc - last_pulse[0]) / F_COUNT;
            chk(to_cs(t1) >= n - 1 && to_cs(t1) <= n + 1, "RUN: counts up at 1 tick / F_COUNT clk");
            tap(4'b0001);
            t1 = p_sw; wait_cyc(5000);
            chk(p_sw == t1, "STOP: count frozen");
            tc_end;

            tc_begin("TC-S02 mode up/down (R-11)");
            tap(4'b0100);                        // STOP: U -> down
            tap(4'b0001); wait_cyc(500); t1 = p_sw; wait_cyc(3000); t2 = p_sw;
            chk(to_cs(t2) < to_cs(t1), "down mode: count decreases");
            tap(4'b0100);                        // RUN: U ignored
            t1 = p_sw; wait_cyc(3000); t2 = p_sw;
            chk(to_cs(t2) < to_cs(t1), "btnU in RUN ignored (still down)");
            tap(4'b0001); tap(4'b0100);          // STOP, U -> up
            tap(4'b0001); wait_cyc(500); t1 = p_sw; wait_cyc(3000); t2 = p_sw;
            chk(to_cs(t2) > to_cs(t1), "up mode: count increases");
            tc_end;

            tc_begin("TC-S03 clear (R-11)");
            tap(4'b0010);                        // RUN: L ignored
            chk(to_cs(p_sw) > 50, "btnL in RUN ignored (not cleared)");
            tap(4'b0001);                        // STOP
            tap(4'b0010);
            chk(p_sw == 0 && p_live == 0, "btnL in STOP -> 00:00:00.00");
            tc_end;

            tc_begin("TC-S04 lap 3 s hold");
            tap(4'b0001); wait_cyc(3000);
            tap(4'b1000); pA = last_pulse[3]; tA = p_lap;
            wait_until(pA + 10000);
            chk(p_sw == tA && to_cs(p_live) > to_cs(tA), "during hold: shows lap, live keeps counting");
            wait_until(pA + HOLD_COUNT - 20);
            chk(p_sw == tA, "still lap at 3 s - 20 clk");
            wait_until(pA + HOLD_COUNT + 20);
            chk(p_sw == p_live, "back to live after 3 s");
            tap(4'b0001);
            tc_end;

            // ===== C-01 / C-02 + 표시 내용 =====
            tc_begin("TC-C01 mode switch + background (R-07)");
            tap(4'b0001);                        // stopwatch RUN
            t1 = p_live; t0 = p_wt;
            set_sw(3'b000); wait_cyc(20000);
            chk(led[1] == 1'b1, "sw0=0 -> led[1]=1 (watch shown)");
            set_sw(3'b001);
            n = to_cs(p_live) - to_cs(t1);
            chk(n >= 199 && n <= 202, "stopwatch kept running while watch shown (~200 ticks)");
            t0 = p_wt; wait_cyc(30000);
            n = to_cs(p_wt) - to_cs(t0);
            chk(n >= 299 && n <= 301, "watch kept running while stopwatch shown (~300 ticks)");
            tap(4'b0001);                        // STOP
            tc_end;

            tc_begin("TC-C02 display unit + R-14a dot");
            // cs 20 근처에서 정지 -> 소수점 켜짐
            tap(4'b0001);
            for (n = 0; n < 20000 && f_c(p_live) != 20; n = n + 1) @(negedge clk);
            tap(4'b0001);
            tS = p_sw;
            set_sw(3'b001); read_display;
            chk(rd[3] == font(f_s(tS)/10) && rd[2] == font(f_s(tS)%10) &&
                rd[1] == font(f_c(tS)/10) && rd[0] == font(f_c(tS)%10), "sw1=0: shows SS.cc of stopwatch");
            chk(led[0] == 1'b0, "sw1=0 -> led[0]=0");
            chk(rd_dot == ((f_c(tS) < 50) ? 8'h7F : 8'hFF), "dot rule R-14a (msec<50 on)");
            set_sw(3'b011); read_display;
            chk(rd[3] == font(f_h(tS)/10) && rd[2] == font(f_h(tS)%10) &&
                rd[1] == font(f_m(tS)/10) && rd[0] == font(f_m(tS)%10), "sw1=1: shows HH.MM of stopwatch");
            chk(led[0] == 1'b1, "sw1=1 -> led[0]=1");
            set_sw(3'b001);
            tap(4'b0001);
            for (n = 0; n < 20000 && f_c(p_live) != 60; n = n + 1) @(negedge clk);
            tap(4'b0001);
            tS = p_sw; read_display;
            chk(rd_dot == ((f_c(tS) < 50) ? 8'h7F : 8'hFF), "dot rule R-14a (msec>=50 off)");
            tc_end;

            // ===== V3 Stopwatch 경계 =====
            tc_begin("TC-E02 down underflow 0 -> 23:59:59.99 (R-03)");
            tap(4'b0010); tap(4'b0100);          // clear, down
            @(negedge clk); bt[0] = 1'b1;          // btnR 누른 채로 첫 변화 감시
            for (n = 0; n < 20000 && p_live == 0; n = n + 1) @(negedge clk);
            wait_cyc(6);
            chk(p_live == pack(23,59,59,99), "first tick after 00:00:00.00 is 23:59:59.99");
            bt[0] = 1'b0; wait_cyc(1500);
            tap(4'b0001);
            chk(f_h(p_live) == 23 && f_m(p_live) == 59 && f_s(p_live) == 59, "keeps counting down (no stop at 0)");
            tc_end;

            tc_begin("TC-E03 up overflow 23:59:59.99 -> 0 (R-02)");
            tap(4'b0100);                        // up
            seen_pre = 1'b0; ok = 1'b0;
            @(negedge clk); bt[0] = 1'b1;          // RUN, 누른 채로 감시
            for (n = 0; n < 20000 && !ok; n = n + 1) begin
                @(negedge clk);
                if (p_live == pack(23,59,59,99)) seen_pre = 1'b1;
                if (f_h(p_live) == 0) ok = 1'b1;
            end
            wait_cyc(6);
            chk(seen_pre && ok && p_live == 0, "23:59:59.99 -> 00:00:00.00 (no stop)");
            bt[0] = 1'b0; wait_cyc(1500);
            tap(4'b0001);
            tc_end;

            tc_begin("TC-E04 sec<->min carry/borrow");
            tap(4'b0010); tap(4'b0001);          // clear, RUN(up)
            seen_pre = 1'b0; ok = 1'b0;
            for (n = 0; n < 700000 && !ok; n = n + 1) begin
                @(negedge clk);
                if (p_live == pack(0,0,59,99)) seen_pre = 1'b1;
                if (f_m(p_live) == 1) ok = 1'b1;
            end
            wait_cyc(6);
            chk(seen_pre && ok && p_live == pack(0,1,0,0), "up: 00:00:59.99 -> 00:01:00.00");
            wait_cyc(1000); tap(4'b0001); tap(4'b0100); tap(4'b0001);   // STOP, down, RUN
            seen_pre = 1'b0; ok = 1'b0;
            for (n = 0; n < 50000 && !ok; n = n + 1) begin
                @(negedge clk);
                if (p_live == pack(0,1,0,0)) seen_pre = 1'b1;
                if (f_m(p_live) == 0) ok = 1'b1;
            end
            wait_cyc(6);
            chk(seen_pre && ok && p_live == pack(0,0,59,99), "down: 00:01:00.00 -> 00:00:59.99");
            tap(4'b0001); tap(4'b0100);          // STOP, up
            tc_end;

            // ===== V3 R-08 =====
            tc_begin("TC-E07 set mode + sw0=1 (R-08)");
            set_sw(3'b100); tap(4'b0010); tap(4'b0010);     // SET_SEC -> MIN -> HOUR
            t0 = p_wt;
            set_sw(3'b101);                                 // sw0=1 (sw2 still 1)
            wait_cyc(2000);
            chk(to_cs(p_wt) - to_cs(t0) >= 19, "watch resumes running (IDLE)");
            chk(dut.w_blink_en == 1'b0, "blink stops (blink_en=0)");
            tS = p_live; n = n_lap; tap(4'b0100);           // U goes to stopwatch (STOP: mode toggle), not to watch
            chk(n_lap == n && p_live == tS, "button routed to stopwatch (watch unchanged, scoreboard)");
            tap(4'b0100);                                   // restore stopwatch mode
            set_sw(3'b100);                                 // back: must restart at SET_SEC
            chk(led[0] == 1'b0, "re-entry shows Sec/Msec (SET_SEC)");
            t0 = p_wt; wait_cyc(3000);
            chk(p_wt == t0, "frozen again");
            probe_field(W_SEC, "re-entry field is SEC (not HOUR)");
            set_sw(3'b000);
            tc_end;

            // ===== V3 R-09 =====
            set_sw(3'b001);
            tc_begin("TC-E08 lap re-capture / stop in hold (R-09)");
            tap(4'b0010); tap(4'b0001);                     // clear, RUN
            wait_cyc(5000);
            tap(4'b1000); pA = last_pulse[3]; tA = p_lap;
            wait_until(pA + 10000);
            tap(4'b1000); pB = last_pulse[3]; tB = p_lap;
            chk(to_cs(tB) > to_cs(tA), "2nd lap captures new value");
            wait_until(pA + HOLD_COUNT + 100);
            chk(p_sw == tB, "hold restarted (still lap B after A+3s)");
            wait_until(pB + HOLD_COUNT - 20);
            chk(p_sw == tB, "lap B until B+3s");
            wait_until(pB + HOLD_COUNT + 20);
            chk(p_sw == p_live, "back to live after B+3s");
            tap(4'b1000); pC = last_pulse[3]; tC = p_lap;
            tap(4'b0001);                                    // STOP during hold
            tS = p_live;
            wait_until(pC + HOLD_COUNT - 20);
            chk(p_sw == tC && tS != tC, "STOP during hold: still shows lap");
            wait_until(pC + HOLD_COUNT + 20);
            chk(p_sw == tS, "after hold: shows stopped value");
            n = n_lap; tap(4'b1000); wait_cyc(5000);
            chk(n_lap == n && p_sw == tS, "btnD in STOP ignored");
            tc_end;

            // ===== V3 R-11 동시 입력 =====
            tc_begin("TC-E09 simultaneous buttons in STOP (R-11)");
            tS = p_live;
            tap(4'b0111);                                    // R+L+U
            wait_cyc(3000);
            chk(to_cs(p_live) > to_cs(tS), "R+L+U: RUN wins, not cleared, still up");
            tap(4'b0001);
            tap(4'b0110);                                    // L+U
            chk(p_live == 0, "L+U: CLEAR wins");
            tap(4'b0001); wait_cyc(3000);
            chk(to_cs(p_live) > 0 && to_cs(p_live) < 1000, "mode unchanged (up)");
            n = n_lap; tap(4'b1001);                          // RUN: R+D (명세 공백, 코드 기준)
            chk(n_lap == n + 1, "RUN R+D: lap captured and STOP (code-defined)");
            wait_cyc(HOLD_COUNT + 100);
            tc_end;

            // ===== V3 R-06 깜빡임 =====
            set_sw(3'b000);
            tc_begin("TC-E10 blink 0.25s/0.25s (R-06)");
            for (n = 0; n < 2000000 && !(p_ds == 2 && (cyc - ds_last_chg) > 1000 && (cyc - ds_last_chg) < 2000); n = n + 1) @(negedge clk);
            @(negedge clk); sw = 3'b100; tE = cyc;
            wait_until(tE + 200);  ok = (fnd_font != 8'hFF);
            wait_until(tE + 1250); ok = ok && (fnd_font != 8'hFF);
            wait_until(tE + 2400); ok = ok && (fnd_font != 8'hFF);
            chk(ok, "entry: selected SEC digit lit for first 0.25 s");
            wait_until(tE + 2700); ok = (fnd_font == 8'hFF);
            wait_until(tE + 3750); ok = ok && (fnd_font == 8'hFF);
            wait_until(tE + 4900); ok = ok && (fnd_font == 8'hFF);
            chk(ok, "next 0.25 s: SEC digit off");
            wait_until(tE + 5200); ok = (fnd_font != 8'hFF);
            wait_until(tE + 7300); ok = ok && (fnd_font != 8'hFF);
            chk(ok, "then lit again (period 0.5 s)");
            chk(p_ds == 2, "  (all samples in same scan slot)");
            for (n = 0; n < 2000000 && !(p_ds == 0 && (cyc - ds_last_chg) > 100); n = n + 1) @(negedge clk);
            ok = 1'b1;
            for (n = 0; n < 40; n = n + 1) begin wait_cyc(250); if (fnd_font == 8'hFF) ok = 1'b0; end
            chk(ok, "non-selected field (msec) always lit");
            for (n = 0; n < 2000000 && !(p_ds == 2 && (cyc - ds_last_chg) > 100 && (cyc - ds_last_chg) < 100000 && fnd_font == 8'hFF); n = n + 1) @(negedge clk);
            set_sw(3'b000); @(negedge clk); sw = 3'b100; wait_cyc(200);
            chk(p_ds == 2 && fnd_font != 8'hFF, "re-entry starts lit");
            for (n = 0; n < 2000000 && p_ds != 6; n = n + 1) @(negedge clk);
            wait_cyc(100);
            chk(fnd_font == 8'h7F, "set mode: dot always on (R-14a)");
            set_sw(3'b000);
            tc_end;

            // ===== FND 스캔 / 체커 요약 =====
            tc_begin("TC-E12 FND scan (R-14) + display checker");
            wait_cyc(SCAN_STEP * 9);
            chk(n_scan >= 16, "ds_sel advanced >= 2 full rounds");
            chk(e_scan == 0, "scan period 125000 clk, 0..7, one-hot-low fnd_com");
            chk(n_fnd > 100 && e_fnd == 0, "FND font samples match model");
            tc_end;
        end
    endtask

    // ------------------------------------------------------------------ 랜덤 스트레스 (V4)
    integer seed, act, r, hi, nb, exp_p;
    reg [3:0] msk;
    integer n_press, n_glitch, n_bounce, n_multi, n_swchg, e_db_cnt;
    integer hr;
    reg [63:0] t_end;

    function integer rnd; input integer lo, hi_;
        rnd = lo + ({$random(seed)} % (hi_ - lo + 1));
    endfunction

    task stress_action;
        begin
            act = rnd(0, 99);
            if (act < 35) begin
                wait_cyc(rnd(1000, 300000));                          // 10 us ~ 3 ms 대기
            end else if (act < 60) begin                                // 유효 누름 1개
                b = rnd(0, 3); hi = (rnd(0, 19) == 0) ? rnd(20000, 300000) : rnd(820, 5000);
                snap_pc; press(4'b0001 << b, hi); n_press = n_press + 1;
                if (pc_total(0) != 1 || pc_delta(b) != 1) begin e_db_cnt = e_db_cnt + 1; sb_err = sb_err + 1; if (sb_err <= 60) $display("[ERR][DEBOUNCE] cyc=%0d valid press %0d clk -> %0d pulse", cyc, hi, pc_total(0)); end
            end else if (act < 70) begin                                // 글리치 (<7 us)
                b = rnd(0, 3); hi = rnd(50, 680);
                snap_pc; press(4'b0001 << b, hi); n_glitch = n_glitch + 1;
                if (pc_total(0) != 0) begin e_db_cnt = e_db_cnt + 1; sb_err = sb_err + 1; if (sb_err <= 60) $display("[ERR][DEBOUNCE] cyc=%0d glitch %0d clk -> %0d pulse", cyc, hi, pc_total(0)); end
            end else if (act < 75) begin                                // 채터링 + 안정
                b = rnd(0, 3); snap_pc; bounce(4'b0001 << b, rnd(1000, 5000)); n_bounce = n_bounce + 1;
                if (pc_total(0) != 1) begin e_db_cnt = e_db_cnt + 1; sb_err = sb_err + 1; if (sb_err <= 60) $display("[ERR][DEBOUNCE] cyc=%0d bounce -> %0d pulse", cyc, pc_total(0)); end
            end else if (act < 80) begin                                // 동시 누름
                msk = rnd(1, 15); snap_pc; press(msk, rnd(820, 3000)); n_multi = n_multi + 1;
                exp_p = msk[0] + msk[1] + msk[2] + msk[3];
                if (pc_total(0) != exp_p) begin e_db_cnt = e_db_cnt + 1; sb_err = sb_err + 1; if (sb_err <= 60) $display("[ERR][DEBOUNCE] cyc=%0d multi %b -> %0d pulse", cyc, msk, pc_total(0)); end
            end else begin                                              // 스위치 변경
                r = rnd(0, 9);
                @(negedge clk);
                if (r < 3) sw[0] = ~sw[0]; else if (r < 6) sw[1] = ~sw[1]; else sw[2] = ~sw[2];
                n_swchg = n_swchg + 1;
                wait_cyc(rnd(1000, 20000));
            end
        end
    endtask

    task checkpoint; input integer h;
        begin
            $write("[V4] HOUR %0d | cyc=%0d | watch ", h, cyc); show(p_wt);
            $write(" | sw_live "); show(p_live);
            $display(" | cmp=%0d fnd=%0d wt_tick=%0d sw_tick=%0d | press=%0d glitch=%0d bounce=%0d multi=%0d sw=%0d lap=%0d set=%0d | ERR=%0d WARN=%0d",
                     n_cmp, n_fnd, n_wt_tick, n_sw_tick, n_press, n_glitch, n_bounce, n_multi, n_swchg, n_lap, n_set_entry, sb_err, sb_warn);
        end
    endtask

    task run_stress;
        begin
            seed = SEED;
            n_press = 0; n_glitch = 0; n_bounce = 0; n_multi = 0; n_swchg = 0; e_db_cnt = 0;
            $display("[V4] random stress start: hours=%0d seed=%0d cycles/hour=%0d", STRESS_HOURS, SEED, CYC_PER_HOUR);
            for (hr = 1; hr <= STRESS_HOURS; hr = hr + 1) begin
                t_end = CYC_PER_HOUR * hr;
                while (cyc < t_end) stress_action;
                checkpoint(hr);
            end
        end
    endtask

    // ------------------------------------------------------------------ 메인
    initial begin
        sb_err = 0; sb_warn = 0; n_cmp = 0; n_fnd = 0; n_wt_tick = 0; n_sw_tick = 0; n_lap = 0; n_set_entry = 0;
        e_wt = 0; e_sw = 0; e_rate = 0; e_rng = 0; e_fnd = 0; e_scan = 0; e_led = 0; e_db = 0; e_lap = 0;
        pcnt0 = 0; pcnt1 = 0; pcnt2 = 0; pcnt3 = 0; db_q = 0; n_scan = 0; ds_last_chg = 0; ds_q = 0; fnd_div = 0;
        tc_n = 0; e_db_cnt = 0;
        for (i = 0; i < 4; i = i + 1) last_pulse[i] = 0;

        $display("==== tb_s2_verif  TEST_MODE=%0d  F_COUNT=%0d HOLD_COUNT=%0d HALF_COUNT=%0d  G=%0d ====",
                 TEST_MODE, F_COUNT, HOLD_COUNT, HALF_COUNT, G);
        $display("defparam check: watch F_COUNT=%0d  stopwatch F_COUNT=%0d  HOLD_COUNT=%0d  HALF_COUNT=%0d",
                 dut.U_WATCH.U_WATCH_DATATPATH.U_TICK_GEN_100HMZ.F_COUNT,
                 dut.U_STOPWATCH.U_STOPWATCH_DATATPATH.U_TICK_GEN_100HMZ.F_COUNT,
                 dut.U_STOPWATCH.U_LAP_MODULE.HOLD_COUNT, dut.U_FND_CNTL.U_BLINK.HALF_COUNT);

        rst = 1'b1; sw = 3'b000; bt = 4'b0000;
        repeat (20) @(negedge clk);
        rst = 1'b0;
        wait_cyc(3);

        if (TEST_MODE == 0) run_directed;
        else                run_stress;

        $display("\n==================== SUMMARY ====================");
        if (TEST_MODE == 0) begin
            for (i = 0; i < tc_n; i = i + 1) $display("  %-40s %0s", tc_name[i], tc_res[i] ? "PASS" : "FAIL");
        end
        $display("  scoreboard compares=%0d  fnd_samples=%0d  scan_steps=%0d  watch_ticks=%0d  sw_ticks=%0d  laps=%0d",
                 n_cmp, n_fnd, n_scan, n_wt_tick, n_sw_tick, n_lap);
        $display("  errors: WATCH=%0d SW=%0d RATE=%0d RANGE=%0d FND=%0d SCAN=%0d LED=%0d DEBOUNCE=%0d LAP=%0d  | total=%0d  WARN(RIPPLE)=%0d",
                 e_wt, e_sw, e_rate, e_rng, e_fnd, e_scan, e_led, e_db + e_db_cnt, e_lap, sb_err, sb_warn);
        n_tc_fail = 0;
        for (i = 0; i < tc_n; i = i + 1) if (!tc_res[i]) n_tc_fail = n_tc_fail + 1;
        $display("  TC: %0d run, %0d fail", tc_n, n_tc_fail);
        $display("  RESULT: %0s", (sb_err == 0 && n_tc_fail == 0) ? "PASS" : "FAIL");
        $display("  sim end cyc=%0d (%0t)", cyc, $time);
        $finish;
    end

endmodule