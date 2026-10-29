`timescale 1ns / 1ps
// ============================================================================
//  tb_stopwatch_watch.v  -  3차 세션 3단계 검증용 테스트벤치
//
//  포함 모듈
//    sww_ref_model   : 01 문서 명세 기반 참조 모델 + 상시 스코어보드
//    tb_sww_func     : 성능 기준 1(11개 TC) + 기준 3(엣지 케이스)  [top 1]
//    tb_sww_stress   : 성능 기준 4(장시간·랜덤 스트레스)          [top 2]
//
//  시간 축소 (defparam, 00 문서 기준 4)
//    10 ms tick   : F_COUNT 1,000,000 -> F            (func F=110, stress F=6)
//    LAP 3 s      : HOLD_COUNT 300,000,000 -> 300*F
//    Blink 0.25 s : HALF_COUNT 25,000,000  -> 25*F
//    btn_debounce(1 MHz 샘플), clk_div_800hz(62,500)는 상수가 코드에 고정되어
//    defparam으로 축소할 수 없으므로 실제 값 그대로 시뮬레이션한다.
//
//  실행 (Vivado): Simulation Sources에 이 파일 추가 -> top을 tb_sww_func 또는
//                 tb_sww_stress로 지정 -> xsim.simulate.runtime = all
//                 스트레스 시간 변경: Simulation Settings > xsim.compile.xvlog.more_options
//                 에 "-d STRESS_HOURS=24" (기본 6). 시드 변경: "-d SEED=1234"
//  실행 (Icarus): iverilog -g2005 -s tb_sww_func -o f.vvp <rtl>/*.v tb_stopwatch_watch.v
//                 vvp f.vvp | tee func.log
//                 iverilog -g2005 -s tb_sww_stress -DSTRESS_HOURS=6 -o s.vvp ...
//
//  판정 출력: [PASS]/[FAIL] <TC-ID>  … 마지막에 SUMMARY 표
//  - 각 TC 시작 시 참조 모델을 DUT 상태로 재동기화하여, 한 TC의 실패가
//    다음 TC로 번지지 않게 한다(스트레스는 매 시간 시작 시).
//  - 경계값은 STOP 상태 또는 Watch 설정 모드에서 카운터에 직접 주입한다(preload).
// ============================================================================


// ============================================================================
//  참조 모델
//   - 입력: 디바운스 출력 펄스(dut.w_sw_btn / dut.w_wt_btn), sw[0], sw[2]
//   - 명세(6-1, 6-2, B-5, B-6 확정본)대로 상태·시간을 계산하고,
//     매 클럭 하강 에지에서 DUT 출력 시간(w_sw_time / w_wt_time)과 비교한다.
//   - 자리올림 전파(1클럭/단)는 명세 밖 구현 지연이므로, 틱 직후 4클럭은
//     비교에서 제외한다(1단계 O-1).
// ============================================================================
module sww_ref_model #(
    parameter integer F    = 100,
    parameter integer HOLD = 30000
)(
    input         clk,
    input         rst,
    input         sw0,
    input         sw2,
    input  [3:0]  wt_btn,       // {D,U,L,R}
    input  [3:0]  sw_btn,       // {D,U,L,R}
    input  [23:0] sw_live_dut,  // LAP 캡처 순간 DUT live 값(캡처 일관성 확인용)
    input  [23:0] dut_sw_time,
    input  [23:0] dut_wt_time
);
    localparam S_STOP = 0, S_RUN = 1, S_CLEAR = 2, S_MODE = 3;
    localparam W_IDLE = 0, W_SEC = 1, W_MIN = 2, W_HOUR = 3;

    // ---------------- stopwatch 모델 상태 ----------------
    integer sh, sm, ss, sms;        // 현재 값
    integer ph, pm, ps, pms;        // 직전 틱 값
    integer sacc, sd, sgap, shcnt;  // 분주 위상, 마지막 틱 이후 클럭 수, 틱 간격
    reg [1:0]  sst;
    reg        smode, shold;
    reg [23:0] slap;
    // ---------------- watch 모델 상태 ----------------
    integer wh, wm, ws, wms;
    integer qh, qm, qs, qms;
    integer wacc, wd, wgap;
    reg [1:0]  wst;

    // ---------------- 스코어보드 ----------------
    integer err_sw, err_wt, err_lap, chk_sw, chk_wt;
    integer print_lim;
    reg     en_check;

    function [23:0] pack;
        input integer h, m, s, ms;
        pack = (h << 19) | (m << 13) | (s << 7) | ms;
    endfunction

    task model_reset;
        begin
            sh = 0; sm = 0; ss = 0; sms = 0; ph = 0; pm = 0; ps = 0; pms = 0;
            sacc = 0; sd = 1000; sgap = 1000; shcnt = 0;
            sst = S_STOP; smode = 1'b0; shold = 1'b0; slap = 24'd0;
            wh = 12; wm = 0; ws = 0; wms = 0; qh = 12; qm = 0; qs = 0; qms = 0;
            wacc = 0; wd = 1000; wgap = 1000; wst = W_IDLE;
        end
    endtask

    initial begin
        model_reset;
        err_sw = 0; err_wt = 0; err_lap = 0; chk_sw = 0; chk_wt = 0;
        print_lim = 30; en_check = 1'b1;
    end

    // TB에서 경계값 주입 시 함께 호출
    task preload_sw;
        input integer h, m, s, ms;
        begin
            sh = h; sm = m; ss = s; sms = ms; ph = h; pm = m; ps = s; pms = ms;
            sd = 1000; sgap = 1000;
        end
    endtask

    task preload_wt;
        input integer h, m, s, ms;
        begin
            wh = h; wm = m; ws = s; wms = ms; qh = h; qm = m; qs = s; qms = ms;
            wd = 1000; wgap = 1000;
        end
    endtask

    // TC 경계에서 DUT 상태로 재동기화 (앞선 TC의 실패가 다음 TC로 번지지 않게)
    task resync;
        input [1:0]   s_st;  input s_md;  input integer s_acc; input [23:0] s_t;
        input         s_hd;  input integer s_hc; input [23:0] s_lp;
        input [1:0]   w_st;  input integer w_acc; input [23:0] w_t;
        begin
            sh = s_t[23:19]; sm = s_t[18:13]; ss = s_t[12:7]; sms = s_t[6:0];
            ph = sh; pm = sm; ps = ss; pms = sms; sd = 1000; sgap = 1000;
            sst = s_st; smode = s_md; sacc = s_acc; shold = s_hd; shcnt = s_hc; slap = s_lp;
            wh = w_t[23:19]; wm = w_t[18:13]; ws = w_t[12:7]; wms = w_t[6:0];
            qh = wh; qm = wm; qs = ws; qms = wms; wd = 1000; wgap = 1000;
            wst = w_st; wacc = w_acc;
        end
    endtask

    task sw_step;
        begin
            ph = sh; pm = sm; ps = ss; pms = sms; sgap = sd + 1; sd = 0;
            if (!smode) begin                               // Count Up (R-02)
                sms = sms + 1;
                if (sms == 100) begin
                    sms = 0; ss = ss + 1;
                    if (ss == 60) begin
                        ss = 0; sm = sm + 1;
                        if (sm == 60) begin
                            sm = 0; sh = sh + 1;
                            if (sh == 24) sh = 0;
                        end
                    end
                end
            end else begin                                  // Count Down (R-03)
                if (sms == 0) begin
                    sms = 99;
                    if (ss == 0) begin
                        ss = 59;
                        if (sm == 0) begin
                            sm = 59;
                            if (sh == 0) sh = 23; else sh = sh - 1;
                        end else sm = sm - 1;
                    end else ss = ss - 1;
                end else sms = sms - 1;
            end
        end
    endtask

    task wt_step;
        begin
            qh = wh; qm = wm; qs = ws; qms = wms; wgap = wd + 1; wd = 0;
            wms = wms + 1;
            if (wms == 100) begin
                wms = 0; ws = ws + 1;
                if (ws == 60) begin
                    ws = 0; wm = wm + 1;
                    if (wm == 60) begin
                        wm = 0; wh = wh + 1;
                        if (wh == 24) wh = 0;                 // R-04
                    end
                end
            end
        end
    endtask

    task wt_adj;                                            // W-01, W-02, R-05
        input integer dir;
        begin
            case (wst)
                W_SEC:  begin ws = (ws + dir + 60) % 60; qs = ws; end
                W_MIN:  begin wm = (wm + dir + 60) % 60; qm = wm; end
                W_HOUR: begin wh = (wh + dir + 24) % 24; qh = wh; end
            endcase
        end
    endtask

    reg     run_pre, wrun_pre, set_en, stepped_s, stepped_w;
    integer sd_b, sgap_b;
    reg [23:0] scur_b, sprev_b;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            model_reset;
        end else begin
            // ===================== Stopwatch =====================
            run_pre = (sst == S_RUN);
            sd_b = sd; sgap_b = sgap;
            scur_b  = pack(sh, sm, ss, sms);
            sprev_b = pack(ph, pm, ps, pms);
            stepped_s = 1'b0;
            if (sst == S_CLEAR) begin                       // S-03, B-6(CLEAR 시 분주 초기화)
                sacc = 0; sh = 0; sm = 0; ss = 0; sms = 0;
                ph = 0; pm = 0; ps = 0; pms = 0; sd = 1000; sgap = 1000;
            end else if (run_pre) begin                     // B-6(STOP 시 분주 위상 유지)
                if (sacc == F - 1) begin sacc = 0; sw_step; stepped_s = 1'b1; end
                else sacc = sacc + 1;
            end
            if (!stepped_s && sd < 1000) sd = sd + 1;

            // LAP (S-04, R-09, B-5): RUN일 때만 수락, 재입력 시 재캡처
            if (sw_btn[3] && run_pre) begin
                if (sd_b >= 4) begin
                    if (sw_live_dut !== scur_b) begin
                        err_lap = err_lap + 1;
                        $display("  [MODEL] %0t LAP capture mismatch dut=%h exp=%h", $time, sw_live_dut, scur_b);
                    end
                end else if (sd_b == 0 && sgap_b >= 4) begin
                    if (sw_live_dut !== sprev_b) begin
                        err_lap = err_lap + 1;
                        $display("  [MODEL] %0t LAP capture mismatch dut=%h exp=%h", $time, sw_live_dut, sprev_b);
                    end
                end
                shold = 1'b1; shcnt = 0; slap = sw_live_dut;
            end else if (shold) begin
                if (shcnt == HOLD - 1) begin shold = 1'b0; shcnt = 0; end
                else shcnt = shcnt + 1;
            end

            // FSM (S-01~S-03, R-11: STOP에서 R > L > U)
            case (sst)
                S_STOP:  if (sw_btn[0]) sst = S_RUN;
                         else if (sw_btn[1]) sst = S_CLEAR;
                         else if (sw_btn[2]) sst = S_MODE;
                S_RUN:   if (sw_btn[0]) sst = S_STOP;
                S_CLEAR: sst = S_STOP;
                S_MODE:  begin smode = ~smode; sst = S_STOP; end
            endcase

            // ===================== Watch =====================
            set_en   = (~sw0) & sw2;                        // C-03, R-08
            wrun_pre = (wst == W_IDLE);
            stepped_w = 1'b0;
            if (wrun_pre) begin
                if (wacc == F - 1) begin wacc = 0; wt_step; stepped_w = 1'b1; end
                else wacc = wacc + 1;
            end
            if (!stepped_w && wd < 1000) wd = wd + 1;

            case (wst)
                W_IDLE: if (set_en) wst = W_SEC;            // R-08: 항상 SEC부터
                default: begin
                    if (!set_en)        wst = W_IDLE;
                    else if (wt_btn[2]) wt_adj(1);          // U
                    else if (wt_btn[3]) wt_adj(-1);         // D
                    else if (wt_btn[1])                     // L: SEC->MIN->HOUR->SEC
                        wst = (wst == W_SEC) ? W_MIN : (wst == W_MIN) ? W_HOUR : W_SEC;
                    else if (wt_btn[0])                     // R: SEC->HOUR->MIN->SEC
                        wst = (wst == W_SEC) ? W_HOUR : (wst == W_HOUR) ? W_MIN : W_SEC;
                end
            endcase
        end
    end

    // ---------------- 비교 (하강 에지) ----------------
    reg [23:0] exp_s, exp_w;
    reg        vs, vw;
    always @(negedge clk) begin
        if (!rst && en_check) begin
            if (shold)                        begin exp_s = slap;                   vs = 1'b1; end
            else if (sd >= 4)                 begin exp_s = pack(sh, sm, ss, sms);  vs = 1'b1; end
            else if (sd == 0 && sgap >= 4)    begin exp_s = pack(ph, pm, ps, pms);  vs = 1'b1; end
            else                                                                    vs = 1'b0;
            if (vs) begin
                chk_sw = chk_sw + 1;
                if (dut_sw_time !== exp_s) begin
                    err_sw = err_sw + 1;
                    if (err_sw <= print_lim)
                        $display("  [MODEL] %0t SW mismatch dut=%0d:%0d:%0d.%0d exp=%0d:%0d:%0d.%0d",
                                 $time, dut_sw_time[23:19], dut_sw_time[18:13], dut_sw_time[12:7], dut_sw_time[6:0],
                                 exp_s[23:19], exp_s[18:13], exp_s[12:7], exp_s[6:0]);
                end
            end

            if (wd >= 4)                      begin exp_w = pack(wh, wm, ws, wms);  vw = 1'b1; end
            else if (wd == 0 && wgap >= 4)    begin exp_w = pack(qh, qm, qs, qms);  vw = 1'b1; end
            else                                                                    vw = 1'b0;
            if (vw) begin
                chk_wt = chk_wt + 1;
                if (dut_wt_time !== exp_w) begin
                    err_wt = err_wt + 1;
                    if (err_wt <= print_lim)
                        $display("  [MODEL] %0t WT mismatch dut=%0d:%0d:%0d.%0d exp=%0d:%0d:%0d.%0d",
                                 $time, dut_wt_time[23:19], dut_wt_time[18:13], dut_wt_time[12:7], dut_wt_time[6:0],
                                 exp_w[23:19], exp_w[18:13], exp_w[12:7], exp_w[6:0]);
                end
            end
        end
    end
endmodule


// ============================================================================
//  기능 + 엣지 케이스 테스트벤치
// ============================================================================
module tb_sww_func;
    // F는 100의 약수가 아니어야 한다: 버튼 펄스가 1 us(100 clk) 격자에 정렬되므로
    // F=100이면 STOP 시점의 분주 위상이 항상 0이 되어 B-6(위상 유지)을 구분할 수 없다.
    localparam integer F    = 110;          // 10 ms  -> 110 clk
    localparam integer HOLD = 300 * F;      // 3 s    -> 33,000 clk
    localparam integer HALF = 25 * F;       // 0.25 s -> 2,750 clk
    localparam integer SCAN = 1125000;      // ds_sel 0~7 한 바퀴(8 x 125,000) + 여유

    localparam [3:0] B_R = 4'b0001, B_L = 4'b0010, B_U = 4'b0100, B_D = 4'b1000;

    reg clk = 1'b0, rst = 1'b1;
    reg btnR = 1'b0, btnL = 1'b0, btnU = 1'b0, btnD = 1'b0;
    reg [2:0] sw = 3'b000;
    wire [3:0] fnd_com;
    wire [7:0] fnd_font;
    wire [1:0] led;

    stopwatch_watch_integrate dut (
        .clk(clk), .rst(rst),
        .btnR(btnR), .btnL(btnL), .btnU(btnU), .btnD(btnD),
        .sw(sw), .fnd_com(fnd_com), .fnd_font(fnd_font), .led(led)
    );
    defparam dut.U_WATCH.U_WATCH_DATATPATH.U_TICK_GEN_100HMZ.F_COUNT          = F;
    defparam dut.U_STOPWATCH.U_STOPWATCH_DATATPATH.U_TICK_GEN_100HMZ.F_COUNT  = F;
    defparam dut.U_STOPWATCH.U_LAP_MODULE.HOLD_COUNT                          = HOLD;
    defparam dut.U_FND_CNTL.U_BLINK.HALF_COUNT                                = HALF;

    always #5 clk = ~clk;

    // ---------------- 관측 신호 ----------------
    wire [3:0]  t_wt_btn  = dut.w_wt_btn;
    wire [3:0]  t_sw_btn  = dut.w_sw_btn;
    wire [23:0] t_sw_time = dut.w_sw_time;
    wire [23:0] t_wt_time = dut.w_wt_time;
    wire [23:0] t_sw_live = {dut.U_STOPWATCH.w_live_hour, dut.U_STOPWATCH.w_live_min,
                             dut.U_STOPWATCH.w_live_sec,  dut.U_STOPWATCH.w_live_msec};
    wire [2:0]  t_ds_sel  = dut.U_FND_CNTL.w_ds_sel;

    sww_ref_model #(.F(F), .HOLD(HOLD)) M (
        .clk(clk), .rst(rst), .sw0(sw[0]), .sw2(sw[2]),
        .wt_btn(t_wt_btn), .sw_btn(t_sw_btn), .sw_live_dut(t_sw_live),
        .dut_sw_time(t_sw_time), .dut_wt_time(t_wt_time)
    );

    // ---------------- 상시 모니터 ----------------
    integer pc_sw0, pc_sw1, pc_sw2, pc_sw3, pc_wt0, pc_wt1, pc_wt2, pc_wt3;
    integer err_pw, err_com, err_led;
    reg [3:0] prev_sw_b, prev_wt_b;
    reg [3:0] exp_com;
    initial begin
        pc_sw0 = 0; pc_sw1 = 0; pc_sw2 = 0; pc_sw3 = 0;
        pc_wt0 = 0; pc_wt1 = 0; pc_wt2 = 0; pc_wt3 = 0;
        err_pw = 0; err_com = 0; err_led = 0; prev_sw_b = 0; prev_wt_b = 0;
    end
    always @(negedge clk) if (!rst) begin
        if (t_sw_btn[0]) pc_sw0 = pc_sw0 + 1;
        if (t_sw_btn[1]) pc_sw1 = pc_sw1 + 1;
        if (t_sw_btn[2]) pc_sw2 = pc_sw2 + 1;
        if (t_sw_btn[3]) pc_sw3 = pc_sw3 + 1;
        if (t_wt_btn[0]) pc_wt0 = pc_wt0 + 1;
        if (t_wt_btn[1]) pc_wt1 = pc_wt1 + 1;
        if (t_wt_btn[2]) pc_wt2 = pc_wt2 + 1;
        if (t_wt_btn[3]) pc_wt3 = pc_wt3 + 1;
        // D-4: 펄스 폭 1클럭, D-5: 동시에 양쪽으로 전달 금지
        if (((t_sw_btn & prev_sw_b) != 0) || ((t_wt_btn & prev_wt_b) != 0) || ((t_sw_btn & t_wt_btn) != 0)) begin
            err_pw = err_pw + 1;
            $display("  [MON] %0t pulse width/routing error sw_btn=%b wt_btn=%b", $time, t_sw_btn, t_wt_btn);
        end
        prev_sw_b = t_sw_btn; prev_wt_b = t_wt_btn;
        // F-1: fnd_com 한 비트만 0, ds_sel[1:0] 대응
        case (t_ds_sel[1:0])
            2'd0: exp_com = 4'b1110;
            2'd1: exp_com = 4'b1101;
            2'd2: exp_com = 4'b1011;
            default: exp_com = 4'b0111;
        endcase
        if (fnd_com !== exp_com) begin
            err_com = err_com + 1;
            if (err_com < 10) $display("  [MON] %0t fnd_com error %b (ds_sel=%0d)", $time, fnd_com, t_ds_sel);
        end
    end
    // F-5: led[1] = ~sw[0]
    always @(posedge clk) if (!rst) begin
        if (led[1] !== ~sw[0]) err_led = err_led + 1;
    end

    // ---------------- 결과 집계 ----------------
    integer n_pass, n_fail, tc_err, n_chk;
    integer e_sw0, e_wt0, e_lap0, e_pw0, e_com0, e_led0;
    reg [8*12:1] tc_id;
    reg [8*12:1] res_id   [0:39];
    reg [8*100:1] res_desc [0:39];
    reg          res_ok   [0:39];
    integer      n_res;
    reg [8*100:1] cur_desc;
    initial begin n_pass = 0; n_fail = 0; n_res = 0; end

    task tc_start;
        input [8*12:1] id;
        input [8*100:1] desc;
        begin
            model_resync;
            tc_id = id; cur_desc = desc; tc_err = 0; n_chk = 0;
            e_sw0 = M.err_sw; e_wt0 = M.err_wt; e_lap0 = M.err_lap;
            e_pw0 = err_pw; e_com0 = err_com; e_led0 = err_led;
            $display("");
            $display("==== %0s : %0s  (t=%0t ns)", id, desc, $time);
        end
    endtask

    task check;
        input        cond;
        input [8*120:1] msg;
        begin
            n_chk = n_chk + 1;
            if (cond) $display("    [CHK-PASS] %0s", msg);
            else begin
                tc_err = tc_err + 1;
                $display("    [CHK-FAIL] %0s", msg);
            end
        end
    endtask

    task tc_end;
        integer ds, dw, dl, dp, dc, dd, tsum;
        begin
            ds = M.err_sw - e_sw0; dw = M.err_wt - e_wt0; dl = M.err_lap - e_lap0;
            dp = err_pw - e_pw0; dc = err_com - e_com0; dd = err_led - e_led0;
            tsum = tc_err + ds + dw + dl + dp + dc + dd;
            $display("    scoreboard: sw_mismatch=%0d wt_mismatch=%0d lap=%0d pulse/route=%0d fnd_com=%0d led1=%0d",
                     ds, dw, dl, dp, dc, dd);
            res_id[n_res] = tc_id; res_desc[n_res] = cur_desc; res_ok[n_res] = (tsum == 0);
            n_res = n_res + 1;
            if (tsum == 0) begin n_pass = n_pass + 1; $display("[PASS] %0s  (directed checks %0d)", tc_id, n_chk); end
            else          begin n_fail = n_fail + 1; $display("[FAIL] %0s  (errors %0d)", tc_id, tsum); end
        end
    endtask

    // ---------------- 시간 헬퍼 ----------------
    function [23:0] T;
        input integer h, m, s, ms;
        T = (h << 19) | (m << 13) | (s << 7) | ms;
    endfunction
    function integer tot;          // 10 ms 단위 총합
        input [23:0] t;
        tot = ((t[23:19] * 60 + t[18:13]) * 60 + t[12:7]) * 100 + t[6:0];
    endfunction

    task show;
        input [8*8:1] tag;
        input [23:0] t;
        $display("      %0s = %02d:%02d:%02d.%02d", tag, t[23:19], t[18:13], t[12:7], t[6:0]);
    endtask

    // 모델 재동기화: 자리올림 전파가 끝난 시점(분주 카운터 >= 5)에서 DUT 상태 복사
    task model_resync;
        integer wc, sc;
        reg ok;
        begin
            ok = 0;
            while (!ok) begin
                @(posedge clk); #2;
                wc = dut.U_WATCH.U_WATCH_DATATPATH.U_TICK_GEN_100HMZ.counter_reg;
                sc = dut.U_STOPWATCH.U_STOPWATCH_DATATPATH.U_TICK_GEN_100HMZ.counter_reg;
                ok = (wc >= 5 || dut.U_WATCH.U_SET_TIME.c_state != 0) &&
                     (sc >= 5 || dut.U_STOPWATCH.U_CONTROL_UNIT.c_state != 1);
            end
            M.resync(dut.U_STOPWATCH.U_CONTROL_UNIT.c_state, dut.U_STOPWATCH.U_CONTROL_UNIT.mode_reg, sc, t_sw_live,
                     dut.U_STOPWATCH.U_LAP_MODULE.hold, dut.U_STOPWATCH.U_LAP_MODULE.hold_cnt,
                     {dut.U_STOPWATCH.U_LAP_MODULE.lap_hour, dut.U_STOPWATCH.U_LAP_MODULE.lap_min,
                      dut.U_STOPWATCH.U_LAP_MODULE.lap_sec,  dut.U_STOPWATCH.U_LAP_MODULE.lap_msec},
                     dut.U_WATCH.U_SET_TIME.c_state, wc, t_wt_time);
            @(negedge clk);
        end
    endtask

    task cyc;   input integer n; begin repeat (n) @(posedge clk); end endtask
    task ticks; input integer n; begin repeat (n * F) @(posedge clk); end endtask

    task settle_sw; begin @(negedge clk); while (!(M.shold || M.sd >= 4)) @(negedge clk); end endtask
    task settle_wt; begin @(negedge clk); while (!(M.wd >= 4)) @(negedge clk); end endtask

    task set_sw;
        input [2:0] v;
        begin @(negedge clk); sw = v; repeat (3) @(negedge clk); end
    endtask

    // 버튼: mask {D,U,L,R}, hold_ns 동안 누른 뒤 30 us 쉼
    task press;
        input [3:0] mask;
        input integer hold_ns;
        begin
            @(negedge clk);
            {btnD, btnU, btnL, btnR} = mask;
            #(hold_ns);
            {btnD, btnU, btnL, btnR} = 4'b0000;
            #(30000);
            @(negedge clk);
        end
    endtask
    task tap; input [3:0] mask; begin press(mask, 20000); end endtask

    // btnD에 임의 폭 high를 넣는다(노이즈 시험용)
    task glitch_d;
        input integer hi_ns;
        input integer off_ns;
        begin
            @(negedge clk); #(off_ns);
            btnD = 1'b1; #(hi_ns); btnD = 1'b0;
            #(20000);
            @(negedge clk);
        end
    endtask

    // 경계값 주입 (STOP 상태 / Watch 설정 모드에서만 사용)
    task preload_sw;
        input integer h, m, s, ms;
        begin
            @(posedge clk); #2;
            dut.U_STOPWATCH.U_STOPWATCH_DATATPATH.U_HOUR_COUNTER.counter_reg = h;
            dut.U_STOPWATCH.U_STOPWATCH_DATATPATH.U_MIN_COUNTER.counter_reg  = m;
            dut.U_STOPWATCH.U_STOPWATCH_DATATPATH.U_SEC_COUNTER.counter_reg  = s;
            dut.U_STOPWATCH.U_STOPWATCH_DATATPATH.U_MSEC_COUNTER.counter_reg = ms;
            M.preload_sw(h, m, s, ms);
            @(negedge clk);
        end
    endtask
    task preload_wt;
        input integer h, m, s, ms;
        begin
            @(posedge clk); #2;
            dut.U_WATCH.U_WATCH_DATATPATH.U_HOUR_COUNTER.counter_reg = h;
            dut.U_WATCH.U_WATCH_DATATPATH.U_MIN_COUNTER.counter_reg  = m;
            dut.U_WATCH.U_WATCH_DATATPATH.U_SEC_COUNTER.counter_reg  = s;
            dut.U_WATCH.U_WATCH_DATATPATH.U_MSEC_COUNTER.counter_reg = ms;
            M.preload_wt(h, m, s, ms);
            @(negedge clk);
        end
    endtask

    // Stopwatch를 STOP / 지정 모드로 맞춘다 (sw0=1 가정)
    task ensure_stop; begin if (M.sst == 1) tap(B_R); cyc(5); end endtask
    task ensure_mode; input m; begin ensure_stop; if (M.smode != m) tap(B_U); cyc(5); end endtask

    // RUN 진입 후 첫 msec 변화까지의 클럭 수 (B-6)
    task first_tick_latency;
        output integer n;
        reg [6:0] ms0;
        begin
            @(negedge clk); btnR = 1'b1;
            while (dut.U_STOPWATCH.w_run_stop !== 1'b1) @(posedge clk);
            #1 ms0 = t_sw_time[6:0]; n = 0;
            while (t_sw_time[6:0] == ms0) begin @(posedge clk); #1 n = n + 1; end
            #(20000) btnR = 1'b0; #(30000); @(negedge clk);
        end
    endtask

    // ---------------- FND 캡처 ----------------
    reg [7:0] cap_font [0:7];
    reg       cap_val  [0:7];
    reg       cap_ff   [0:7];
    reg       cap_dot  [0:7];
    reg       cap_inc  [0:7];
    integer   ci;
    task fnd_capture;
        input integer ncyc;
        integer k, d;
        begin
            for (ci = 0; ci < 8; ci = ci + 1) begin
                cap_font[ci] = 8'hFF; cap_val[ci] = 0; cap_ff[ci] = 0; cap_dot[ci] = 0; cap_inc[ci] = 0;
            end
            for (k = 0; k < ncyc; k = k + 1) begin
                @(negedge clk);
                d = t_ds_sel;
                if (fnd_font == 8'hFF)      cap_ff[d] = 1;
                else if (fnd_font == 8'h7F) cap_dot[d] = 1;
                else begin
                    if (cap_val[d] && cap_font[d] != fnd_font) cap_inc[d] = 1;
                    cap_val[d] = 1; cap_font[d] = fnd_font;
                end
            end
        end
    endtask
    function integer f2d;
        input [7:0] f;
        case (f)
            8'hC0: f2d = 0; 8'hF9: f2d = 1; 8'hA4: f2d = 2; 8'hB0: f2d = 3; 8'h99: f2d = 4;
            8'h92: f2d = 5; 8'h82: f2d = 6; 8'hF8: f2d = 7; 8'h80: f2d = 8; 8'h90: f2d = 9;
            default: f2d = -1;
        endcase
    endfunction
    // ds 위치 d가 숫자 v를 표시했고, 깜빡임 여부가 blink와 같은지
    function digit_ok;
        input integer d, v;
        input blink;
        digit_ok = cap_val[d] && !cap_inc[d] && (f2d(cap_font[d]) == v) && (cap_ff[d] == blink) && !cap_dot[d];
    endfunction
    function blank_ok;              // ds 4,5,7: 항상 소등
        input integer d;
        blank_ok = !cap_val[d] && !cap_dot[d] && cap_ff[d];
    endfunction

    // ---------------- LAP 관찰 ----------------
    // btnD를 눌러 펄스를 확인한 뒤, 캡처 에지 직후의 표시값을 돌려준다
    task lap_cap;
        output [23:0] lapv;
        begin
            @(negedge clk); btnD = 1'b1;
            while (t_sw_btn[3] !== 1'b1) @(negedge clk);
            @(posedge clk); #1 lapv = t_sw_time;
            btnD = 1'b0;
        end
    endtask

    // btnD를 눌러 LAP 캡처 후, 표시값이 바뀔 때까지의 클럭 수(n)를 잰다.
    // 관찰 중 a1/a2 시점에 다른 버튼을 2,000클럭 동안 누른다.
    task lap_observe;
        input  [3:0] a1_mask; input integer a1_at;
        input  [3:0] a2_mask; input integer a2_at;
        output integer n;
        output [23:0] lapv;
        output [23:0] after;
        integer c, pc, done;
        begin
            @(negedge clk); btnD = 1'b1; pc = 0;
            while (t_sw_btn[3] !== 1'b1) begin @(negedge clk); pc = pc + 1; end
            @(posedge clk); #1 lapv = t_sw_time;
            n = -1; c = 0; done = 0;
            while (!done) begin
                @(posedge clk); #1 c = c + 1; pc = pc + 1;
                if (pc == 2000) btnD = 1'b0;
                if (a1_mask != 0 && c == a1_at)        {btnD, btnU, btnL, btnR} = {btnD, btnU, btnL, btnR} | a1_mask;
                if (a1_mask != 0 && c == a1_at + 2000) {btnD, btnU, btnL, btnR} = {btnD, btnU, btnL, btnR} & ~a1_mask;
                if (a2_mask != 0 && c == a2_at)        {btnD, btnU, btnL, btnR} = {btnD, btnU, btnL, btnR} | a2_mask;
                if (a2_mask != 0 && c == a2_at + 2000) {btnD, btnU, btnL, btnR} = {btnD, btnU, btnL, btnR} & ~a2_mask;
                if (n < 0 && t_sw_time !== lapv) n = c;
                if (n >= 0 && c > a1_at + 4000 && c > a2_at + 4000 && c > n + 2 * F) done = 1;
                if (c > 3 * HOLD) begin done = 1; end
            end
            {btnD, btnU, btnL, btnR} = 4'b0000;
            settle_sw; after = t_sw_time;
        end
    endtask

    // =======================================================================
    //  시나리오
    // =======================================================================
    reg [23:0] a, b, c2, d2, lv, af, lv2;
    integer    n1, n2, k, p0, p1, w0, acc_at_stop, lat, ph;
    integer    kk;

    initial begin
        $display("tb_sww_func start: F=%0d HOLD=%0d HALF=%0d", F, HOLD, HALF);
        #100; @(negedge clk); rst = 1'b0;
        cyc(2);

        // ------------------------------------------------------------------
        tc_start("R-04", "Reset state (reference only, not a scored TC)");
        check(t_wt_time == T(12,0,0,0), "Watch = 12:00:00.00 after reset");
        check(t_sw_time == 0,           "Stopwatch = 00:00:00.00 after reset");
        ticks(5); settle_wt; settle_sw;
        check(tot(t_wt_time) > tot(T(12,0,0,0)), "Watch runs right after reset");
        check(t_sw_time == 0, "Stopwatch stays STOP");
        tc_end;

        // ==================================================================
        //  성능 기준 1 : 01 문서 6-1의 11개 TC
        // ==================================================================
        tc_start("W-01", "Watch set: Btn U +1, wrap, other fields unchanged");
        set_sw(3'b100);                                  // sw0=0, sw2=1 -> SET_SEC
        check(dut.w_set_field == 3'b101, "SEC selected on entry");
        preload_wt(5,30,58,42);
        tap(B_U); settle_wt; show("wt", t_wt_time);
        check(t_wt_time == T(5,30,59,42), "SEC 58 -> 59");
        tap(B_U); settle_wt; show("wt", t_wt_time);
        check(t_wt_time == T(5,30,0,42),  "SEC 59 -> 00, MIN unchanged");
        tap(B_L);                                        // -> MIN
        preload_wt(5,59,0,42);
        tap(B_U); settle_wt; show("wt", t_wt_time);
        check(t_wt_time == T(5,0,0,42),   "MIN 59 -> 00, HOUR unchanged");
        tap(B_L);                                        // -> HOUR
        preload_wt(23,0,0,42);
        tap(B_U); settle_wt; show("wt", t_wt_time);
        check(t_wt_time == T(0,0,0,42),   "HOUR 23 -> 00");
        tap(B_U); settle_wt;
        check(t_wt_time == T(1,0,0,42),   "HOUR 00 -> 01");
        tap(B_L);                                        // -> SEC
        tc_end;

        tc_start("W-02", "Watch set: Btn D -1, 00 -> max");
        preload_wt(10,20,0,42);
        tap(B_D); settle_wt; show("wt", t_wt_time);
        check(t_wt_time == T(10,20,59,42), "SEC 00 -> 59, MIN unchanged");
        tap(B_D); settle_wt;
        check(t_wt_time == T(10,20,58,42), "SEC 59 -> 58");
        tap(B_L);                                        // -> MIN
        preload_wt(10,0,58,42);
        tap(B_D); settle_wt; show("wt", t_wt_time);
        check(t_wt_time == T(10,59,58,42), "MIN 00 -> 59, HOUR unchanged");
        tap(B_L);                                        // -> HOUR
        preload_wt(0,59,58,42);
        tap(B_D); settle_wt; show("wt", t_wt_time);
        check(t_wt_time == T(23,59,58,42), "HOUR 00 -> 23");
        tap(B_L);                                        // -> SEC
        tc_end;

        tc_start("W-03", "Watch set: Btn L/R moves field (+ R-06 blink position)");
        preload_wt(10,20,30,42);
        // 시작 SEC. 순서: R,R,R,L,L,L  기대: HOUR, MIN, SEC, MIN, HOUR, SEC
        for (kk = 0; kk < 6; kk = kk + 1) begin
            if (kk < 3) tap(B_R); else tap(B_L);
            settle_wt; a = t_wt_time;
            tap(B_U); settle_wt; b = t_wt_time;
            case (kk)
                0, 4: check(b == T((a[23:19]+1)%24, a[18:13], a[12:7], a[6:0]) && dut.w_set_field == 3'b111 && dut.w_disp_mode == 2'b11,
                            "HOUR selected (U changes HOUR only)");
                1, 3: check(b == T(a[23:19], (a[18:13]+1)%60, a[12:7], a[6:0]) && dut.w_set_field == 3'b110 && dut.w_disp_mode == 2'b11,
                            "MIN selected (U changes MIN only)");
                default: check(b == T(a[23:19], a[18:13], (a[12:7]+1)%60, a[6:0]) && dut.w_set_field == 3'b101 && dut.w_disp_mode == 2'b10,
                            "SEC selected (U changes SEC only)");
            endcase
            tap(B_D); settle_wt;
            check(t_wt_time == a, "restored by D");
            // 깜빡임 위치 확인 (각 필드 첫 방문 시)
            if (kk == 0 || kk == 1 || kk == 2) begin
                fnd_capture(SCAN);
                a = t_wt_time;
                if (kk == 0)      check(cap_ff[2] && cap_ff[3] && cap_val[2] && cap_val[3] && !cap_ff[0] && !cap_ff[1]
                                        && digit_ok(0, a[18:13]%10, 0) && digit_ok(1, a[18:13]/10, 0)
                                        && f2d(cap_font[2]) == a[23:19]%10 && f2d(cap_font[3]) == a[23:19]/10,
                                        "SET_HOUR: Hour/Min view, only hour digits blink");
                else if (kk == 1) check(cap_ff[0] && cap_ff[1] && cap_val[0] && cap_val[1] && !cap_ff[2] && !cap_ff[3]
                                        && digit_ok(2, a[23:19]%10, 0) && digit_ok(3, a[23:19]/10, 0)
                                        && f2d(cap_font[0]) == a[18:13]%10 && f2d(cap_font[1]) == a[18:13]/10,
                                        "SET_MIN: Hour/Min view, only min digits blink");
                else              check(cap_ff[2] && cap_ff[3] && cap_val[2] && cap_val[3] && !cap_ff[0] && !cap_ff[1]
                                        && digit_ok(0, a[6:0]%10, 0) && digit_ok(1, a[6:0]/10, 0)
                                        && f2d(cap_font[2]) == a[12:7]%10 && f2d(cap_font[3]) == a[12:7]/10,
                                        "SET_SEC: Sec/Msec view, only sec digits blink");
            end
        end
        tc_end;

        tc_start("W-04", "Watch set: long press (3 ms) -> recognized once");
        settle_wt; a = t_wt_time; p0 = pc_wt2;
        press(B_U, 3000000); settle_wt; b = t_wt_time;
        check(pc_wt2 - p0 == 1, "exactly 1 debounced pulse");
        check(b == T(a[23:19], a[18:13], (a[12:7]+1)%60, a[6:0]), "SEC +1 only");
        set_sw(3'b000);                                  // 설정 해제
        tc_end;

        tc_start("S-01", "Stopwatch Btn R: STOP<->RUN (+ B-6 prescaler kept on STOP)");
        set_sw(3'b001);
        ensure_mode(0); preload_sw(0,0,0,0);
        tap(B_R); ticks(20); settle_sw; a = t_sw_time;
        ticks(20); settle_sw; b = t_sw_time;
        check(dut.U_STOPWATCH.w_run_stop == 1 && tot(b) > tot(a), "count increases after RUN");
        @(negedge clk); btnR = 1'b1;
        while (t_sw_btn[0] !== 1'b1) @(negedge clk);
        @(posedge clk); #1 acc_at_stop = M.sacc;          // STOP 시점 분주 위상
        #(20000) btnR = 1'b0; #(30000);
        settle_sw; a = t_sw_time; ticks(20); settle_sw; b = t_sw_time;
        check(dut.U_STOPWATCH.w_run_stop == 0 && a == b, "count frozen after STOP");
        first_tick_latency(lat);
        $display("      prescaler phase at STOP=%0d, first msec change after RUN = %0d clk (kept: %0d, reset: %0d)",
                 acc_at_stop, lat, F - acc_at_stop, F);
        if (acc_at_stop == 0) $display("      [NOTE] stopped at phase 0: keep/reset not distinguishable");
        check(lat == F - acc_at_stop, "B-6: prescaler kept after STOP");
        ensure_stop;
        tc_end;

        tc_start("S-02", "Stopwatch Btn U: Up<->Down (+ R-11 U ignored in RUN)");
        ensure_mode(0); preload_sw(0,0,10,0);
        tap(B_U);                                        // -> Down
        check(dut.U_STOPWATCH.w_mode == 1, "U in STOP -> Down mode");
        tap(B_R); ticks(30); settle_sw; a = t_sw_time;
        ticks(30); settle_sw; b = t_sw_time;
        check(tot(b) < tot(a), "count decreases in Down mode");
        tap(B_U); ticks(10); settle_sw; c2 = t_sw_time;
        ticks(20); settle_sw; d2 = t_sw_time;
        check(dut.U_STOPWATCH.w_mode == 1 && tot(d2) < tot(c2), "R-11: U ignored in RUN (still decreasing)");
        tap(B_R);                                        // STOP
        tap(B_U);                                        // -> Up
        check(dut.U_STOPWATCH.w_mode == 0, "U in STOP -> Up mode");
        tap(B_R); ticks(20); settle_sw; a = t_sw_time;
        ticks(20); settle_sw; b = t_sw_time;
        check(tot(b) > tot(a), "count increases in Up mode");
        tap(B_R);
        tc_end;

        tc_start("S-03", "Stopwatch Btn L: CLEAR (+ R-11 accept/priority, B-6 prescaler reset)");
        ensure_mode(0); preload_sw(1,2,3,4);
        tap(B_L); settle_sw;
        check(t_sw_time == 0, "L in STOP -> 00:00:00.00");
        preload_sw(0,0,1,0);
        tap(B_R); ticks(10); tap(B_L); ticks(10); settle_sw; a = t_sw_time;
        check(tot(a) > 100, "R-11: L ignored in RUN");
        tap(B_R);                                        // STOP
        preload_sw(0,0,2,0);
        tap(B_R | B_L | B_U); ticks(20); settle_sw; a = t_sw_time;
        check(dut.U_STOPWATCH.w_run_stop == 1 && dut.U_STOPWATCH.w_mode == 0 && tot(a) > 200,
              "R-11: R+L+U together in STOP -> RUN only");
        tap(B_R);
        preload_sw(0,0,3,0);
        tap(B_L | B_U); settle_sw;
        check(t_sw_time == 0 && dut.U_STOPWATCH.w_mode == 0, "R-11: L+U together in STOP -> CLEAR only (mode kept)");
        first_tick_latency(lat);
        $display("      first msec change after CLEAR+RUN = %0d clk (expect %0d)", lat, F);
        check(lat == F, "B-6: prescaler reset by CLEAR");
        ensure_stop;
        tc_end;

        tc_start("S-04", "Stopwatch Btn D: LAP holds 3 s then returns (+ R-09, B-5)");
        ensure_mode(0); preload_sw(0,0,0,0);
        tap(B_R); ticks(50);
        lap_observe(0, 0, 0, 0, n1, lv, af);
        $display("      lap held %0d clk (expect %0d)", n1, HOLD);
        check(n1 >= HOLD - 1 && n1 <= HOLD + 1, "captured value held for 3 s (HOLD)");
        check(tot(af) > tot(lv) + 250, "internal count runs during hold, live value after");
        // R-09: 유지 중 STOP
        lap_observe(B_R, 3000, 0, 0, n1, lv, af);
        settle_sw; ticks(10); settle_sw;
        check(n1 >= HOLD - 1 && n1 <= HOLD + 1 && af == t_sw_time && af != lv,
              "R-09: STOP during hold -> stopped value after 3 s");
        // R-09: 유지 중 재입력 -> 재캡처, 3 s 처음부터
        tap(B_R); ticks(20);
        lap_cap(lv); cyc(6000);
        lap_cap(lv2);
        n2 = 0;
        while (t_sw_time === lv2 && n2 < 3 * HOLD) begin @(posedge clk); #1 n2 = n2 + 1; end
        $display("      re-captured value held %0d clk (expect %0d)", n2, HOLD);
        check(tot(lv2) > tot(lv) && n2 >= HOLD - 1 && n2 <= HOLD + 1, "R-09: D during hold -> new capture, 3 s restarts");
        settle_sw;
        // R-09: STOP에서 D 무시
        ensure_stop; cyc(HOLD); p0 = pc_sw3;
        tap(B_D);
        @(negedge clk); btnR = 1'b1;
        while (t_sw_btn[0] !== 1'b1) @(negedge clk);
        a = t_sw_time; n2 = 0;
        while (t_sw_time === a && n2 < 3 * HOLD) begin @(posedge clk); #1 n2 = n2 + 1; end
        btnR = 1'b0; #(30000);
        check(pc_sw3 - p0 == 1 && n2 < 2 * F + 10, "R-09: D ignored in STOP (display runs right after RUN)");
        // B-5: 유지 중 STOP + CLEAR -> 3 s 동안 lap 유지 후 00:00:00.00
        ticks(30);
        lap_observe(B_R, 3000, B_L, 9000, n1, lv, af);
        check(n1 >= HOLD - 1 && n1 <= HOLD + 1 && af == 0, "B-5: CLEAR during hold -> lap kept 3 s, then 00:00:00.00");
        ensure_stop;
        tc_end;

        tc_start("C-01", "sw0: 0=Watch / 1=Stopwatch display, other value kept");
        set_sw(3'b001); ensure_stop; preload_sw(12,34,56,78);
        fnd_capture(SCAN);
        check(digit_ok(3,5,0) && digit_ok(2,6,0) && digit_ok(1,7,0) && digit_ok(0,8,0),
              "sw0=1: Stopwatch shows 56.78 (sec10 sec1 msec10 msec1)");
        check(blank_ok(4) && blank_ok(5) && blank_ok(7) && !cap_val[6] && !cap_dot[6],
              "ds_sel 4/5/7 blank, dot off when msec>=50 (F-4)");
        check(led[1] == 1'b0 && led[0] == 1'b0, "led[1]=0(Stopwatch), led[0]=0(Sec/Msec)");
        set_sw(3'b100);                                  // Watch, 설정 모드(시간 고정)
        preload_wt(7,8,9,10);
        fnd_capture(SCAN);
        check(digit_ok(3,0,1) && digit_ok(2,9,1) && digit_ok(1,1,0) && digit_ok(0,0,0),
              "sw0=0: Watch shows 09.10 (sec blinking)");
        check(led[1] == 1'b1, "led[1]=1(Watch)");
        check(t_sw_time == T(12,34,56,78), "Stopwatch value kept while Watch shown");
        set_sw(3'b001); ticks(20); settle_wt;
        check(tot(t_wt_time) > tot(T(7,8,9,10)), "Watch runs while Stopwatch shown (R-07)");
        tc_end;

        tc_start("C-02", "sw1: 0=Sec/Msec / 1=Hour/Min, value kept");
        set_sw(3'b001); ensure_stop; preload_sw(12,34,56,21);
        fnd_capture(SCAN);
        check(digit_ok(3,5,0) && digit_ok(2,6,0) && digit_ok(1,2,0) && digit_ok(0,1,0) && cap_dot[6] && !cap_val[6],
              "sw1=0: shows 56.21, dot on (msec<50)");
        check(led[0] == 1'b0, "led[0]=0");
        set_sw(3'b011);
        fnd_capture(SCAN);
        check(digit_ok(3,1,0) && digit_ok(2,2,0) && digit_ok(1,3,0) && digit_ok(0,4,0),
              "sw1=1: shows 12.34 (Hour/Min)");
        check(led[0] == 1'b1, "led[0]=1");
        check(t_sw_time == T(12,34,56,21), "value kept across sw1 change");
        set_sw(3'b010); cyc(5);
        check(led[0] == 1'b1 && led[1] == 1'b1, "sw1 applies to Watch IDLE (led[0]=1)");
        set_sw(3'b000); cyc(5);
        check(led[0] == 1'b0, "Watch sw1=0 -> led[0]=0");
        tc_end;

        tc_start("C-03", "sw2: Watch set mode enter/exit, time frozen (+ R-05, R-06)");
        set_sw(3'b000); ticks(5);
        // ds_sel=2(초 1의 자리) 구간 시작에서 진입하여 깜빡임 시작 위상 확인
        while (t_ds_sel != 3'd1) @(negedge clk);
        while (t_ds_sel != 3'd2) @(negedge clk);
        settle_wt; a = t_wt_time;
        sw = 3'b100; k = 0; n1 = -1;
        while (t_ds_sel == 3'd2 && n1 < 0) begin
            @(negedge clk); k = k + 1;
            if (fnd_font == 8'hFF) n1 = k;
        end
        $display("      first blank after entry = %0d clk (expect %0d~%0d)", n1, HALF, HALF + 3);
        check(n1 >= HALF && n1 <= HALF + 3, "R-06: starts lit on entry, blank after 0.25 s");
        settle_wt; a = t_wt_time; ticks(30); settle_wt; b = t_wt_time;
        check(dut.w_disp_mode[1] == 1'b1 && a == b, "sw2=1: set mode, time frozen");
        check(t_sw_time == T(12,34,56,21), "Stopwatch value kept");
        @(negedge clk); sw = 3'b000;
        @(negedge clk); c2 = t_wt_time;
        check(c2[6:0] == a[6:0], "R-05: msec kept on exit (not zeroed)");
        ticks(20); settle_wt;
        check(dut.w_disp_mode == 2'b00 && tot(t_wt_time) > tot(a), "sw2=0: watch runs again");
        tc_end;

        // ==================================================================
        //  성능 기준 3 : 엣지 케이스
        // ==================================================================
        // (1) 자리별 올림/내림
        tc_start("E1-1", "Watch 23:59:59.95 -> 00:00:00.xx (day wrap)");
        set_sw(3'b100); preload_wt(23,59,59,95); set_sw(3'b000);
        ticks(10); settle_wt; show("wt", t_wt_time);
        check(t_wt_time[23:7] == 0 && t_wt_time[6:0] >= 2 && t_wt_time[6:0] <= 9, "00:00:00.0x");
        tc_end;

        tc_start("E1-2", "Watch 12:59:59.95 -> 13:00:00 (min->hour carry)");
        set_sw(3'b100); preload_wt(12,59,59,95); set_sw(3'b000);
        ticks(10); settle_wt; show("wt", t_wt_time);
        check(t_wt_time[23:7] == T(13,0,0,0) >> 7, "13:00:00");
        tc_end;

        tc_start("E1-3", "Watch 09:09:59.98 -> 09:10:00 (sec->min carry)");
        set_sw(3'b100); preload_wt(9,9,59,98); set_sw(3'b000);
        ticks(10); settle_wt; show("wt", t_wt_time);
        check(t_wt_time[23:7] == T(9,10,0,0) >> 7, "09:10:00");
        tc_end;

        tc_start("E1-4", "Stopwatch Up 23:59:59.95 -> 00:00:00.xx, no stop (R-02)");
        set_sw(3'b001); ensure_mode(0); preload_sw(23,59,59,95);
        tap(B_R); settle_sw; show("sw", t_sw_time);
        check(t_sw_time[23:7] == 0, "passes 00:00:00");
        a = t_sw_time; ticks(10); settle_sw;
        check(tot(t_sw_time) > tot(a), "keeps increasing after wrap");
        tap(B_R);
        tc_end;

        tc_start("E1-5", "Stopwatch Up 00:59:59.97 -> 01:00:00 (min->hour carry)");
        ensure_mode(0); preload_sw(0,59,59,97);
        tap(B_R); settle_sw; show("sw", t_sw_time);
        check(t_sw_time[23:7] == T(1,0,0,0) >> 7, "01:00:00");
        tap(B_R);
        tc_end;

        tc_start("E1-6", "Stopwatch Down 01:00:00.02 -> 00:59:59.xx (hour borrow)");
        ensure_mode(1); preload_sw(1,0,0,2);
        tap(B_R); settle_sw; show("sw", t_sw_time);
        check(t_sw_time[23:7] == T(0,59,59,0) >> 7, "00:59:59");
        tap(B_R);
        tc_end;

        tc_start("E1-7", "Stopwatch Down 10:00:00.01 -> 09:59:59.xx");
        ensure_mode(1); preload_sw(10,0,0,1);
        tap(B_R); settle_sw; show("sw", t_sw_time);
        check(t_sw_time[23:7] == T(9,59,59,0) >> 7, "09:59:59");
        tap(B_R);
        tc_end;

        // (4) Count Down 언더플로
        tc_start("E4-1", "Stopwatch Down 00:00:00.03 -> 23:59:59.xx, no stop (R-03)");
        ensure_mode(1); preload_sw(0,0,0,3);
        tap(B_R); settle_sw; show("sw", t_sw_time);
        check(t_sw_time[23:7] == T(23,59,59,0) >> 7, "wraps to 23:59:59");
        a = t_sw_time; ticks(10); settle_sw;
        check(tot(t_sw_time) < tot(a), "keeps decreasing after wrap");
        tap(B_R); ensure_mode(0);
        tc_end;

        // (2) 버튼 노이즈 (sw0=1, STOP 상태의 btnD: 명세상 무시되는 입력이라 부작용 없음)
        tc_start("E2-1", "Debounce: 6.0 us high x10 phases -> 0 pulse");
        set_sw(3'b001); ensure_stop; p0 = pc_sw3;
        for (kk = 0; kk < 10; kk = kk + 1) glitch_d(6000, 110 * kk + 1);
        check(pc_sw3 == p0, "no pulse");
        tc_end;

        tc_start("E2-2", "Debounce: 6.9 us high x10 phases -> 0 pulse");
        p0 = pc_sw3;
        for (kk = 0; kk < 10; kk = kk + 1) glitch_d(6900, 110 * kk + 1);
        check(pc_sw3 == p0, "no pulse");
        tc_end;

        tc_start("E2-3", "Debounce: 8.0 us high x10 phases -> 1 pulse each");
        p0 = pc_sw3;
        for (kk = 0; kk < 10; kk = kk + 1) glitch_d(8000, 110 * kk + 1);
        check(pc_sw3 - p0 == 10, "10 pulses");
        tc_end;

        tc_start("E2-4", "Debounce: 9 us / 12 us high x10 phases -> 1 pulse each");
        p0 = pc_sw3;
        for (kk = 0; kk < 10; kk = kk + 1) begin glitch_d(9000, 110 * kk + 1); glitch_d(12000, 90 * kk + 3); end
        check(pc_sw3 - p0 == 20, "20 pulses");
        tc_end;

        tc_start("E2-5", "Debounce: press/release bounce (2~3 us highs) -> 1 pulse");
        p0 = pc_sw3;
        @(negedge clk);
        for (kk = 0; kk < 5; kk = kk + 1) begin btnD = 1; #2000; btnD = 0; #1500; end
        btnD = 1; #30000;
        for (kk = 0; kk < 5; kk = kk + 1) begin btnD = 0; #1500; btnD = 1; #3000; end
        btnD = 0; #30000; @(negedge clk);
        check(pc_sw3 - p0 == 1, "1 pulse");
        tc_end;

        tc_start("E2-6", "Debounce B-2: low (>=1 us) during press, then high >=8 us -> pulse again");
        p0 = pc_sw3;
        for (kk = 0; kk < 5; kk = kk + 1) begin
            @(negedge clk); #(110 * kk + 3);
            btnD = 1; #20000; btnD = 0; #1000; btnD = 1; #20000; btnD = 0; #30000;
            @(negedge clk); #(110 * kk + 3);
            btnD = 1; #20000; btnD = 0; #3000; btnD = 1; #20000; btnD = 0; #30000;
        end
        check(pc_sw3 - p0 == 20, "low 1.0 us / 3.0 us, 5 each x 2 pulses = 20");
        tc_end;

        tc_start("E2-7", "D-5 routing: pulse goes to one unit by sw0");
        set_sw(3'b001); p0 = pc_sw3; w0 = pc_wt3;
        tap(B_D);
        check(pc_sw3 - p0 == 1 && pc_wt3 == w0, "sw0=1 -> Stopwatch only");
        set_sw(3'b000); p0 = pc_sw3; w0 = pc_wt3;
        tap(B_D);
        check(pc_wt3 - w0 == 1 && pc_sw3 == p0, "sw0=0 -> Watch only (R-10: ignored in IDLE)");
        tc_end;

        // (3) 모드 전환 경계
        tc_start("E3-1", "R-08: sw0=1 during SET_MIN -> IDLE and run, re-entry starts at SEC");
        set_sw(3'b100); tap(B_L);
        check(dut.w_set_field == 3'b110, "in SET_MIN");
        @(negedge clk); sw = 3'b101; cyc(3);
        check(dut.w_disp_mode == 2'b00 && dut.w_blink_en == 1'b0, "sw0=1 -> IDLE, blink stops");
        settle_wt; a = t_wt_time; ticks(20); settle_wt;
        check(tot(t_wt_time) > tot(a), "watch runs again");
        @(negedge clk); sw = 3'b100; cyc(3);
        check(dut.w_set_field == 3'b101, "sw0=0, sw2=1 -> restarts at SET_SEC");
        a = t_wt_time; tap(B_U); settle_wt;
        check(t_wt_time == T(a[23:19], a[18:13], (a[12:7]+1)%60, a[6:0]), "U changes SEC after re-entry");
        set_sw(3'b000);
        tc_end;

        tc_start("E3-2", "R-07: both run in background, only Watch in set mode stops");
        set_sw(3'b001); ensure_mode(0); preload_sw(0,0,0,0); tap(B_R);
        settle_sw; a = t_sw_time;
        set_sw(3'b000); ticks(100); set_sw(3'b001); settle_sw;
        check(tot(t_sw_time) >= tot(a) + 100, "Stopwatch runs while Watch shown");
        settle_wt; a = t_wt_time; ticks(100); settle_wt;
        check(tot(t_wt_time) >= tot(a) + 100, "Watch runs while Stopwatch shown");
        settle_sw; a = t_sw_time; set_sw(3'b100); settle_wt; b = t_wt_time; ticks(50);
        settle_wt; c2 = t_wt_time; set_sw(3'b001); settle_sw;
        check(b == c2 && tot(t_sw_time) >= tot(a) + 50, "Watch set: only Watch stops, Stopwatch runs");
        tap(B_R);
        tc_end;

        tc_start("E3-3", "D-5 edge: sw0 changed mid-press -> pulse goes by sw0 at pulse time");
        set_sw(3'b001); ensure_stop; p0 = pc_sw3; w0 = pc_wt3;
        @(negedge clk); btnD = 1; #4000; sw = 3'b000; #20000; btnD = 0; #30000; @(negedge clk);
        check(pc_wt3 - w0 == 1 && pc_sw3 == p0, "sw0 1->0 before pulse -> Watch only");
        p0 = pc_sw3; w0 = pc_wt3;
        @(negedge clk); btnD = 1; #4000; sw = 3'b001; #20000; btnD = 0; #30000; @(negedge clk);
        check(pc_sw3 - p0 == 1 && pc_wt3 == w0, "sw0 0->1 before pulse -> Stopwatch only");
        tc_end;

        // ------------------------------------------------------------------
        $display("");
        $display("================================ SUMMARY ================================");
        for (kk = 0; kk < n_res; kk = kk + 1)
            $display("%0s  %0s  %0s", res_ok[kk] ? "[PASS]" : "[FAIL]", res_id[kk], res_desc[kk]);
        $display("--------------------------------------------------------------------------");
        $display("TOTAL PASS=%0d FAIL=%0d | scoreboard checks sw=%0d wt=%0d, mismatch sw=%0d wt=%0d lap=%0d",
                 n_pass, n_fail, M.chk_sw, M.chk_wt, M.err_sw, M.err_wt, M.err_lap);
        $display("monitor: pulse/route=%0d fnd_com=%0d led1=%0d | sim time %0t ns", err_pw, err_com, err_led, $time);
        $display("==========================================================================");
        $finish;
    end
endmodule


// ============================================================================
//  장시간·랜덤 스트레스 테스트벤치
//   - 시뮬레이션 시간 1시간 = 360,000 tick = 360,000*F clk
//   - 매 시간: 고정 미니 스위트(기준 1·3 기능) + 랜덤 동작, 스코어보드 상시 비교
// ============================================================================
module tb_sww_stress;
`ifdef STRESS_HOURS
    localparam integer HOURS = `STRESS_HOURS;
`else
    localparam integer HOURS = 6;
`endif
`ifdef SEED
    localparam integer SEED0 = `SEED;
`else
    localparam integer SEED0 = 20261024;
`endif
    localparam integer F    = 6;            // >=4 (비교 정렬), 100의 약수 아님(B-6 위상 다양화)
    localparam integer HOLD = 300 * F;
    localparam integer HALF = 25 * F;
    localparam integer CPH  = 360000 * F;       // 1시간당 클럭

    localparam [3:0] B_R = 4'b0001, B_L = 4'b0010, B_U = 4'b0100, B_D = 4'b1000;

    reg clk = 1'b0, rst = 1'b1;
    reg btnR = 0, btnL = 0, btnU = 0, btnD = 0;
    reg [2:0] sw = 3'b001;
    wire [3:0] fnd_com; wire [7:0] fnd_font; wire [1:0] led;

    stopwatch_watch_integrate dut (
        .clk(clk), .rst(rst), .btnR(btnR), .btnL(btnL), .btnU(btnU), .btnD(btnD),
        .sw(sw), .fnd_com(fnd_com), .fnd_font(fnd_font), .led(led)
    );
    defparam dut.U_WATCH.U_WATCH_DATATPATH.U_TICK_GEN_100HMZ.F_COUNT          = F;
    defparam dut.U_STOPWATCH.U_STOPWATCH_DATATPATH.U_TICK_GEN_100HMZ.F_COUNT  = F;
    defparam dut.U_STOPWATCH.U_LAP_MODULE.HOLD_COUNT                          = HOLD;
    defparam dut.U_FND_CNTL.U_BLINK.HALF_COUNT                                = HALF;

    always #5 clk = ~clk;

    wire [3:0]  t_wt_btn  = dut.w_wt_btn;
    wire [3:0]  t_sw_btn  = dut.w_sw_btn;
    wire [23:0] t_sw_time = dut.w_sw_time;
    wire [23:0] t_wt_time = dut.w_wt_time;
    wire [23:0] t_sw_live = {dut.U_STOPWATCH.w_live_hour, dut.U_STOPWATCH.w_live_min,
                             dut.U_STOPWATCH.w_live_sec,  dut.U_STOPWATCH.w_live_msec};
    wire [2:0]  t_ds_sel  = dut.U_FND_CNTL.w_ds_sel;

    sww_ref_model #(.F(F), .HOLD(HOLD)) M (
        .clk(clk), .rst(rst), .sw0(sw[0]), .sw2(sw[2]),
        .wt_btn(t_wt_btn), .sw_btn(t_sw_btn), .sw_live_dut(t_sw_live),
        .dut_sw_time(t_sw_time), .dut_wt_time(t_wt_time)
    );

    integer cyc_cnt;  initial cyc_cnt = 0;
    always @(posedge clk) cyc_cnt = cyc_cnt + 1;

    // 상시 모니터
    integer pcount, err_pw, err_com, err_noise;
    reg [3:0] prev_b, exp_com;
    initial begin pcount = 0; err_pw = 0; err_com = 0; err_noise = 0; prev_b = 0; end
    always @(negedge clk) if (!rst) begin
        if ((t_sw_btn | t_wt_btn) != 0) pcount = pcount + 1;
        if ((((t_sw_btn | t_wt_btn) & prev_b) != 0) || ((t_sw_btn & t_wt_btn) != 0)) err_pw = err_pw + 1;
        prev_b = t_sw_btn | t_wt_btn;
        case (t_ds_sel[1:0])
            2'd0: exp_com = 4'b1110; 2'd1: exp_com = 4'b1101; 2'd2: exp_com = 4'b1011; default: exp_com = 4'b0111;
        endcase
        if (fnd_com !== exp_com) err_com = err_com + 1;
    end

    integer seed;
    function integer rnd;
        input integer n;
        rnd = ($random(seed) & 32'h7fffffff) % n;
    endfunction

    // 모델 재동기화: 자리올림 전파가 끝난 시점(분주 카운터 >= 5)에서 DUT 상태 복사
    task model_resync;
        integer wc, sc;
        reg ok;
        begin
            ok = 0;
            while (!ok) begin
                @(posedge clk); #2;
                wc = dut.U_WATCH.U_WATCH_DATATPATH.U_TICK_GEN_100HMZ.counter_reg;
                sc = dut.U_STOPWATCH.U_STOPWATCH_DATATPATH.U_TICK_GEN_100HMZ.counter_reg;
                ok = (wc >= 5 || dut.U_WATCH.U_SET_TIME.c_state != 0) &&
                     (sc >= 5 || dut.U_STOPWATCH.U_CONTROL_UNIT.c_state != 1);
            end
            M.resync(dut.U_STOPWATCH.U_CONTROL_UNIT.c_state, dut.U_STOPWATCH.U_CONTROL_UNIT.mode_reg, sc, t_sw_live,
                     dut.U_STOPWATCH.U_LAP_MODULE.hold, dut.U_STOPWATCH.U_LAP_MODULE.hold_cnt,
                     {dut.U_STOPWATCH.U_LAP_MODULE.lap_hour, dut.U_STOPWATCH.U_LAP_MODULE.lap_min,
                      dut.U_STOPWATCH.U_LAP_MODULE.lap_sec,  dut.U_STOPWATCH.U_LAP_MODULE.lap_msec},
                     dut.U_WATCH.U_SET_TIME.c_state, wc, t_wt_time);
            @(negedge clk);
        end
    endtask

    task cyc; input integer n; begin repeat (n) @(posedge clk); end endtask
    task press;
        input [3:0] mask; input integer hold_ns;
        begin
            @(negedge clk); {btnD, btnU, btnL, btnR} = mask;
            #(hold_ns); {btnD, btnU, btnL, btnR} = 4'b0000; #(30000); @(negedge clk);
        end
    endtask
    task tap; input [3:0] mask; begin press(mask, 20000); end endtask
    task set_sw; input [2:0] v; begin @(negedge clk); sw = v; repeat (3) @(negedge clk); end endtask

    task preload_sw;
        input integer h, m, s, ms;
        begin
            @(posedge clk); #2;
            dut.U_STOPWATCH.U_STOPWATCH_DATATPATH.U_HOUR_COUNTER.counter_reg = h;
            dut.U_STOPWATCH.U_STOPWATCH_DATATPATH.U_MIN_COUNTER.counter_reg  = m;
            dut.U_STOPWATCH.U_STOPWATCH_DATATPATH.U_SEC_COUNTER.counter_reg  = s;
            dut.U_STOPWATCH.U_STOPWATCH_DATATPATH.U_MSEC_COUNTER.counter_reg = ms;
            M.preload_sw(h, m, s, ms); @(negedge clk);
        end
    endtask
    task preload_wt;
        input integer h, m, s, ms;
        begin
            @(posedge clk); #2;
            dut.U_WATCH.U_WATCH_DATATPATH.U_HOUR_COUNTER.counter_reg = h;
            dut.U_WATCH.U_WATCH_DATATPATH.U_MIN_COUNTER.counter_reg  = m;
            dut.U_WATCH.U_WATCH_DATATPATH.U_SEC_COUNTER.counter_reg  = s;
            dut.U_WATCH.U_WATCH_DATATPATH.U_MSEC_COUNTER.counter_reg = ms;
            M.preload_wt(h, m, s, ms); @(negedge clk);
        end
    endtask

    // 노이즈: 1~6 us high (펄스가 나오면 안 됨)
    task noise;
        input integer bidx; input integer hi_ns;
        integer p0;
        begin
            p0 = pcount;
            @(negedge clk);
            case (bidx) 0: btnR = 1; 1: btnL = 1; 2: btnU = 1; default: btnD = 1; endcase
            #(hi_ns);
            {btnD, btnU, btnL, btnR} = 4'b0000;
            #(20000); @(negedge clk);
            if (pcount != p0) begin
                err_noise = err_noise + 1;
                $display("  [STRESS] %0t pulse generated by noise (%0d ns)", $time, hi_ns);
            end
        end
    endtask

    // 매 시간 고정 미니 스위트: 6-1 기능과 엣지 동작을 한 번씩 수행
    task mini_suite;
        reg [2:0] sv;
        begin
            sv = sw;
            set_sw(3'b001);
            if (M.sst == 1) tap(B_R);
            if (M.smode) tap(B_U);                 // Up 모드
            tap(B_L);                              // S-03 CLEAR
            tap(B_R); cyc(2000);                   // S-01 RUN
            tap(B_D); cyc(2 * HOLD);               // S-04 LAP
            tap(B_R);                              // STOP
            tap(B_U);                              // S-02 Down
            preload_sw(0, 0, 0, 20);
            tap(B_R); cyc(400 * F);                // R-03 언더플로 통과
            tap(B_R); tap(B_U);                    // STOP, Up
            preload_sw(23, 59, 59, 90);
            tap(B_R); cyc(400 * F); tap(B_R);      // R-02 순환 통과
            set_sw(3'b100);                        // C-03 / W-01~03
            tap(B_U); tap(B_L); tap(B_D); tap(B_L); tap(B_U); tap(B_R); tap(B_R);
            press(B_U, 2000000);                   // W-04
            set_sw(3'b000);
            set_sw(3'b010); set_sw(3'b000);        // C-02
            noise(rnd(4), 1000 + rnd(5000));       // 노이즈
            set_sw(sv & 3'b011);
        end
    endtask

    integer hour, op, gap, e_sw0, e_wt0, e_lap0, e_pw0, e_com0, e_n0, nops, hour_fail, kk;
    integer op_cnt [0:9];
    initial begin
        seed = SEED0;
        for (kk = 0; kk < 10; kk = kk + 1) op_cnt[kk] = 0;
        hour_fail = 0;
        $display("tb_sww_stress start: HOURS=%0d F=%0d (1h = %0d clk) SEED=%0d", HOURS, F, CPH, SEED0);
        #100; @(negedge clk); rst = 1'b0;

        for (hour = 1; hour <= HOURS; hour = hour + 1) begin
            model_resync;
            e_sw0 = M.err_sw; e_wt0 = M.err_wt; e_lap0 = M.err_lap;
            e_pw0 = err_pw; e_com0 = err_com; e_n0 = err_noise; nops = 0;
            mini_suite;
            while (cyc_cnt < hour * CPH) begin
                op = rnd(10); op_cnt[op] = op_cnt[op] + 1; nops = nops + 1;
                case (op)
                    0: tap(B_R);
                    1: tap(B_L);
                    2: tap(B_U);
                    3: tap(B_D);
                    4: set_sw({sw[2], sw[1], ~sw[0]});
                    5: set_sw({sw[2], ~sw[1], sw[0]});
                    6: begin                                   // Watch 설정 세션
                           set_sw({1'b1, sw[1], 1'b0});
                           for (kk = 0; kk < 1 + rnd(4); kk = kk + 1)
                               case (rnd(4)) 0: tap(B_U); 1: tap(B_D); 2: tap(B_L); default: tap(B_R); endcase
                           set_sw({1'b0, sw[1], rnd(2) ? 1'b1 : 1'b0});
                       end
                    7: noise(rnd(4), 1000 + rnd(5000));
                    8: begin                                   // 경계값 주입
                           if (rnd(2) == 0) begin
                               if (M.sst == 0) begin
                                   if (M.smode) preload_sw(0, 0, 0, 10 + rnd(50));
                                   else         preload_sw(23, 59, 59, 40 + rnd(50));
                               end
                           end else begin
                               set_sw({1'b1, sw[1], 1'b0});
                               preload_wt(23, 59, 59, 40 + rnd(50));
                               set_sw({1'b0, sw[1], sw[0]});
                           end
                       end
                    default: press(1 << rnd(4), 1000000 + rnd(2000000));   // 길게 누름
                endcase
                gap = 10000 + rnd(90000);
                if (cyc_cnt + gap > hour * CPH) gap = (hour * CPH > cyc_cnt) ? hour * CPH - cyc_cnt : 0;
                cyc(gap);
            end
            kk = (M.err_sw - e_sw0) + (M.err_wt - e_wt0) + (M.err_lap - e_lap0) + (err_pw - e_pw0)
               + (err_com - e_com0) + (err_noise - e_n0);
            if (kk != 0) hour_fail = hour_fail + 1;
            $display("[%s] HOUR %0d : ops=%0d mismatch sw=%0d wt=%0d lap=%0d pulse=%0d fnd_com=%0d noise=%0d | wt=%02d:%02d:%02d sw=%02d:%02d:%02d (chk sw=%0d wt=%0d)",
                     (kk == 0) ? "PASS" : "FAIL", hour, nops,
                     M.err_sw - e_sw0, M.err_wt - e_wt0, M.err_lap - e_lap0, err_pw - e_pw0, err_com - e_com0, err_noise - e_n0,
                     t_wt_time[23:19], t_wt_time[18:13], t_wt_time[12:7], t_sw_time[23:19], t_sw_time[18:13], t_sw_time[12:7],
                     M.chk_sw, M.chk_wt);
        end
        $display("============================ STRESS SUMMARY ============================");
        $display("HOURS=%0d  FAILED_HOURS=%0d  total mismatch sw=%0d wt=%0d lap=%0d pulse=%0d fnd_com=%0d noise=%0d",
                 HOURS, hour_fail, M.err_sw, M.err_wt, M.err_lap, err_pw, err_com, err_noise);
        $display("ops: R=%0d L=%0d U=%0d D=%0d sw0=%0d sw1=%0d set=%0d noise=%0d preload=%0d long=%0d",
                 op_cnt[0], op_cnt[1], op_cnt[2], op_cnt[3], op_cnt[4], op_cnt[5], op_cnt[6], op_cnt[7], op_cnt[8], op_cnt[9]);
        $display("RESULT: %s", (hour_fail == 0) ? "PASS" : "FAIL");
        $display("=========================================================================");
        $finish;
    end
endmodule