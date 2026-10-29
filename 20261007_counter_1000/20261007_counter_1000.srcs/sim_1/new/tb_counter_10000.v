`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/10/07 14:12:07
// Design Name: 
// Module Name: tb_counter_10000
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


// module tb_counter_10000();
//     reg clk, reset;
//     // wire o_tick;
//     reg [2:0] sw;
//     wire [13:0] counter;

//     // Test bench 1
//     // tick_gen dut(
//     //     .clk(clk),
//     //     .reset(reset),
//     //     .o_tick(o_tick)
//     // );

//     // tick_counter dut1(
//     //     .clk(clk),
//     //     .reset(reset),
//     //     .i_tick(o_tick),
//     //     .counter(counter)
//     // );

//     // Test bench 2
//     counter_datapath dut(
//         .clk(clk),
//         .reset(reset),
//         .sw(sw),
//         .counter(counter)
//     );

//     // Generate Clock (Reverse clock signal every 5ns)
//     always #5 clk = ~clk;

//     initial begin
//         clk = 0;
//         reset = 1;
//         #10;
//         reset = 0;

//         // TEST CASE #1 : stop, up
//         sw = 3'b000;
//         dut.U_TICK_COUNTER.counter_reg = 14'd9998;
//         repeat(3) #(10_000_000 * 10);
//         // $stop;

//         // TEST CASE #2 : run, up
//         sw = 3'b001;
//         repeat(3) #(10_000_000 * 10);
//         // $stop;

//         // TEST CASE #3 : clear
//         sw = 3'b010;
//         repeat(3) #(10_000_000 * 10);
//         // $stop;

//         // TEST CASE #4 : clear + run (priority : clear > run)
//         sw = 3'b011;
//         dut.U_TICK_COUNTER.counter_reg = 14'd9998;   // check clear, when value is not 0
//         repeat(3) #(10_000_000 * 10);
//         // $stop;

//         // TEST CASE #5 : stop, down
//         sw = 3'b100;
//         dut.U_TICK_COUNTER.counter_reg = 14'd1;
//         repeat(3) #(10_000_000 * 10);
//         // $stop;

//         // TEST CASE #6 : run, down (check circulation)
//         sw = 3'b101;
//         repeat(3) #(10_000_000 * 10);
//         // $stop;

//         // TEST CASE #7 : clear, down
//         sw = 3'b110;
//         dut.U_TICK_COUNTER.counter_reg = 14'd1;
//         repeat(3) #(10_000_000 * 10);
//         // $stop;

//         // TEST CASE #8 : clear + run, down
//         sw = 3'b111;
//         dut.U_TICK_COUNTER.counter_reg = 14'd1;
//         repeat(3) #(10_000_000 * 10);
//         // $stop;
//         $finish;
//     end
// endmodule

// button simulation
module tb_counter_10000_btn();
    reg clk, reset, btnU, btnL, btnR;
    wire [3:0] fnd_com;
    wire [7:0] fnd_font;

    counter_10000 dut(
        .clk(clk),
        .reset(reset),
        .btnU(btnU),
        .btnL(btnL),
        .btnR(btnR),
        .fnd_com(fnd_com),
        .fnd_font(fnd_font)
    );

    always #5 clk = ~clk;

    initial begin 
        clk = 0;
        reset = 1;
        btnU = 0;
        btnL = 0;
        btnR = 0;
        #10 reset = 0;

        // Test case 1 : runstop btn 1 push-pop
        btnR = 1;
        repeat(1000) @(posedge clk);
        btnR = 0;

        repeat(3) begin
            # (10_000_000 * 10);
        end

        btnR = 1;
        repeat(1000) @(posedge clk);
        btnR = 0;
        $finish;
    end
endmodule
