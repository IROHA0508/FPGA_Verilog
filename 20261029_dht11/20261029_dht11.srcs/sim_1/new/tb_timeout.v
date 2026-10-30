`timescale 1ns / 1ps
module tb_timeout ();
    reg clk = 0, rst = 1, start = 0, us_tick = 0;
    wire valid; wire [15:0] hum, temp;
    tri1 dht11_io;
    integer cnt = 0;
    always #5 clk = ~clk;
    always @(posedge clk) begin cnt <= (cnt == 99) ? 0 : cnt + 1; us_tick <= (cnt == 99); end

    dht11_controller dut (.clk(clk), .rst(rst), .dht11_start(start), .us_tick(us_tick),
        .valid(valid), .humidity(hum), .temperature(temp), .dht11_io(dht11_io));
    dht11_model_fault sensor (.dio(dht11_io));

    // 상태 전환 기록 (IDLE로 돌아올 때 어디서 왔는지)
    reg [2:0] prev = 0; time t_state = 0;
    always @(posedge clk) if (dut.c_state != prev) begin
        if (dut.c_state == 0)
            $display("    %0t us: %0d -> IDLE (그 상태에 %0d us 머묾, bit_cnt=%0d)",
                     $time/1000, prev, ($time - t_state)/1000, dut.bit_cnt_reg);
        prev <= dut.c_state; t_state = $time;
    end

    task press; begin @(posedge clk); start = 1; @(posedge clk); start = 0; end endtask
    task report(input [8*24-1:0] name);
        $display("%0s: state=%0d valid=%b hum=%h temp=%h", name, dut.c_state, valid, hum, temp);
    endtask

    initial begin
        #100 rst = 0; #1000;
        $display("[1] 정상");
        fork sensor.send(40'h37_00_18_03_52, 40, 0); press; join  #300_000; report("    결과");
        $display("[2] 센서 무응답 (선이 계속 HIGH)");
        fork sensor.no_response; press; join          #2_000_000; report("    결과");
        $display("[3] 10비트 보내고 끊김 (HIGH로 멈춤)");
        fork sensor.send(40'h37_00_18_03_52, 10, 0); press; join  #500_000; report("    결과");
        $display("[4] 10비트 보내고 LOW로 고착 400us");
        fork sensor.send(40'h37_00_18_03_52, 10, 1); press; join  #500_000; report("    결과");
        $display("[5] 고장 뒤 다시 정상 측정");
        fork sensor.send(40'h41_00_1A_05_60, 40, 0); press; join  #300_000; report("    결과");
        $finish;
    end
    initial begin #200_000_000; $display("TIMEOUT state=%0d", dut.c_state); $finish; end
endmodule

// DHT11 모델 + 고장 시나리오
module dht11_model_fault (inout dio);
    reg drive_low = 1'b0;
    integer k;
    assign dio = drive_low ? 1'b0 : 1'bz;

    task wait_start;
        begin @(negedge dio); @(posedge dio); end
    endtask

    // nbits개만 보내고 선을 놓음 (40이면 정상), stuck_low=1이면 마지막에 LOW 고착
    task send(input [39:0] d, input integer nbits, input stuck_low);
        begin
            wait_start;
            #25_000 drive_low = 1; #80_000 drive_low = 0; #80_000;
            for (k = 39; k > 39 - nbits; k = k - 1) begin
                drive_low = 1; #50_000; drive_low = 0;
                if (d[k]) #70_000; else #27_000;
            end
            if (nbits == 40) begin drive_low = 1; #50_000; drive_low = 0; end
            else if (stuck_low) begin drive_low = 1; #400_000; drive_low = 0; end
        end
    endtask

    task no_response;   // 시작 신호는 받지만 아무 응답도 안 함
        wait_start;
    endtask
endmodule