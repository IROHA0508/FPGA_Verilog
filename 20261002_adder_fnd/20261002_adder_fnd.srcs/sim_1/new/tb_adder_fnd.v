`timescale 1ns / 1ps

module tb_adder_fnd();

    reg clk, reset;
    wire o_clk_800hz;

    clk_div_800hz DUT(
        .clk(clk),
        .reset(reset),
        .o_clk_800hz(o_clk_800hz)
    );

    // generate 100MHz clock
    // Duty ratio 1:1
    // 5ns마다 항상 반전해라
    always #5 clk = ~clk;

    initial begin
        
        clk = 0;
        // 비동기식 reset → FPGA 설계 로직은 보통 비동기식 사용
        reset = 0;
        #1;
        reset = 1;
        #10;
        reset = 0;
        
        // 아래: (250_000 clk * 10nsec(1 clock cycle time))
        // 2 clock 정도는 보기 위해서. 1 clock → 125_000 clk이므로 2 clock → 250_000.
        // 1 clock 당 10ns 걸림 → 10ns 곱해줌
        #(250_000 * 10);
        #100;
        $stop;
    end

endmodule