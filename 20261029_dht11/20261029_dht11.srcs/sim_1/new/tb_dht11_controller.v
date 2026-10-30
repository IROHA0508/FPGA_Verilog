`timescale 1ns / 1ps

// =====================================================================
// dht11_controller 테스트벤치 (정상 동작만, 타임아웃 제외)
//  - DHT11 센서를 데이터시트 타이밍대로 흉내 내는 모델 포함
//  - 확인 항목: ① 8개 상태를 모두 거치는지
//              ② BIT 상태를 정확히 40번 거치는지 (40비트 수신)
//              ③ humidity / temperature / valid 값이 맞는지
// =====================================================================
module tb_dht11_controller ();

    // -----------------------------------------------------------------
    // 클록, us_tick (100MHz, 100클록마다 1클록 폭 tick = 1us)
    // -----------------------------------------------------------------
    reg clk = 1'b0, rst = 1'b1, start = 1'b0, us_tick = 1'b0;
    integer clk_cnt = 0;

    always #5 clk = ~clk;
    always @(posedge clk) begin
        clk_cnt <= (clk_cnt == 99) ? 0 : clk_cnt + 1;
        us_tick <= (clk_cnt == 99);
    end

    // -----------------------------------------------------------------
    // 단일 선 버스: 풀업 저항 + 센서는 0을 낼 때만 끌어내림 (부록 A)
    // -----------------------------------------------------------------
    wire dht11_io;
    reg  sensor_low = 1'b0;
    pullup (dht11_io);
    assign dht11_io = sensor_low ? 1'b0 : 1'bz;

    // -----------------------------------------------------------------
    // DUT
    // -----------------------------------------------------------------
    wire        valid;
    wire [15:0] humidity, temperature;

    dht11_controller dut (
        .clk        (clk),
        .rst        (rst),
        .dht11_start(start),
        .us_tick    (us_tick),
        .valid      (valid),
        .humidity   (humidity),
        .temperature(temperature),
        .dht11_io   (dht11_io)
    );

    // -----------------------------------------------------------------
    // 상태 이름 (출력용)
    // -----------------------------------------------------------------
    function [8*9-1:0] state_name(input [2:0] s);
        case (s)
            0: state_name = "IDLE";
            1: state_name = "START";
            2: state_name = "WAIT";
            3: state_name = "SYNC_L";
            4: state_name = "SYNC_H";
            5: state_name = "DATA_SYNC";
            6: state_name = "BIT";
            7: state_name = "STOP";
        endcase
    endfunction

    // -----------------------------------------------------------------
    // 상태 감시: 거친 상태 기록, BIT 진입 횟수 세기, 전환 출력
    //   (DATA_SYNC <-> BIT 왕복 80번은 출력하지 않고 횟수만 셈)
    // -----------------------------------------------------------------
    reg [7:0] visited;      // visited[n] = 1 : 상태 n을 거쳤음
    integer   bit_entries;  // BIT 상태에 들어간 횟수
    reg [2:0] prev_state = 0;

    always @(posedge clk) begin
        visited[dut.c_state] <= 1'b1;
        if (dut.c_state != prev_state) begin
            if (dut.c_state == 6) bit_entries = bit_entries + 1;
            if (!((prev_state == 5 && dut.c_state == 6) || (prev_state == 6 && dut.c_state == 5)))
                $display("  %8.1f us : %0s -> %0s", $realtime / 1000.0,
                         state_name(prev_state), state_name(dut.c_state));
            prev_state <= dut.c_state;
        end
    end

    // -----------------------------------------------------------------
    // 센서 모델: 시작 신호를 확인하고 40비트를 보냄 (데이터시트 5장)
    // -----------------------------------------------------------------
    integer k;
    time    t_fall;

    task sensor_respond(input [39:0] data);
        begin
            @(negedge dht11_io);  t_fall = $time;           // FPGA가 LOW로 끌어내림
            @(posedge dht11_io);                             // FPGA가 HIGH로 올림
            if ($time - t_fall < 18_000_000)
                $display("  [MODEL] start LOW too short (< 18ms): %0t ns", $time - t_fall);
            else
                $display("  [MODEL] start LOW %0d us detected", ($time - t_fall) / 1000);

            #35_000;                                         // 20~40us 뒤 응답 시작
            sensor_low = 1'b1; #80_000;                      // 응답 LOW 80us
            sensor_low = 1'b0; #80_000;                      // 응답 HIGH 80us
            for (k = 39; k >= 0; k = k - 1) begin           // MSB first
                sensor_low = 1'b1; #50_000;                  // 비트 시작 LOW 50us
                sensor_low = 1'b0;
                if (data[k]) #70_000;                        // '1' : HIGH 70us
                else         #27_000;                        // '0' : HIGH 26~28us
            end
            sensor_low = 1'b1; #50_000;                      // 끝 LOW 50us
            sensor_low = 1'b0;                               // 선을 놓음 → 풀업으로 HIGH
        end
    endtask

    // -----------------------------------------------------------------
    // 측정 한 번 실행 + 결과 확인
    // -----------------------------------------------------------------
    integer pass_cnt = 0, fail_cnt = 0;

    task run_test(input [39:0] data, input exp_valid, input [8*64-1:0] desc);
        begin
            $display("\n[TEST] %0s  (data sent = %h)", desc, data);
            visited     = 8'b0;
            bit_entries = 0;

            fork
                sensor_respond(data);
                begin                                        // 버튼 1클록 펄스
                    @(posedge clk) start = 1'b1;
                    @(posedge clk) start = 1'b0;
                end
            join

            wait (dut.c_state == 0);                         // IDLE로 돌아올 때까지
            repeat (10) @(posedge clk);

            $display("  result: humidity=%h (%0d.%0d%%)  temperature=%h (%0d.%0d C)  valid=%b",
                     humidity, humidity[15:8], humidity[7:0],
                     temperature, temperature[15:8], temperature[7:0], valid);

            check(visited == 8'hFF,          "all 8 states visited");
            check(bit_entries == 40,         "BIT entered 40 times (40 bits)");
            check(humidity    == data[39:24], "humidity matches");
            check(temperature == data[23:8],  "temperature matches");
            check(valid       == exp_valid,   exp_valid ? "valid = 1 (checksum ok)"
                                                        : "valid = 0 (checksum error)");
            #1_000_000;                                      // 다음 측정 전 1ms 쉼
        end
    endtask

    task check(input cond, input [8*64-1:0] what);
        begin
            if (cond) begin pass_cnt = pass_cnt + 1; $display("  PASS  %0s", what); end
            else begin
                fail_cnt = fail_cnt + 1;
                $display("  FAIL  %0s  (visited=%b, bit_entries=%0d)", what, visited, bit_entries);
            end
        end
    endtask

    // -----------------------------------------------------------------
    // 시나리오
    //   데이터 = 습도정수 | 습도소수 | 온도정수 | 온도소수 | checksum
    //   checksum = 앞 4바이트의 합에서 하위 8비트
    // -----------------------------------------------------------------
    initial begin
        #100 rst = 1'b0;
        #1000;

        // 1) 일반적인 값: 55.0%, 24.3C   37+00+18+03 = 52
        run_test(40'h37_00_18_03_52, 1'b1, "55.0% / 24.3C");

        // 2) 다른 값: 90.0%, 50.9C        5A+00+32+09 = 95
        run_test(40'h5A_00_32_09_95, 1'b1, "90.0% / 50.9C");

        // 3) 0과 1이 몰린 패턴 + 합이 255를 넘는 경우
        //    FF+00+FF+00 = 1FE -> 하위 8비트 FE
        run_test(40'hFF_00_FF_00_FE, 1'b1, "all 1 / all 0 bytes, checksum wrap");

        // 4) checksum이 틀린 경우 (값은 받지만 valid = 0)
        run_test(40'h37_00_18_03_00, 1'b0, "wrong checksum");

        $display("\n==============================");
        $display(" PASS %0d / FAIL %0d", pass_cnt, fail_cnt);
        $display("==============================");
        $finish;
    end

endmodule