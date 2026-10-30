`timescale 1ns / 1ps

module top_dht11 (
    input        clk,
    input        rst,
    input        btnR,
    input        sw,
    output [3:0] fnd_com,
    output [7:0] fnd_font,
    output       valid,
    inout        dht11_io
);

    wire        w_us_tick;
    wire        w_dht11_start;
    wire [13:0] w_dht11_data;

    fnd_controller U_FND_CNTL (
        .clk     (clk),
        .reset   (rst),
        .fnd_data(w_dht11_data),
        .fnd_com (fnd_com),
        .fnd_font(fnd_font)
    );

    dht11_module U_DHT11 (
        .clk        (clk),
        .rst        (rst),
        .dht11_start(w_dht11_start),  // start trigger
        .us_tick    (w_us_tick),
        .disp_mode  (sw),
        .valid      (valid),          // check sum ok
        .data       (w_dht11_data),
        .dht11_io   (dht11_io)        // single wire for half duplexing
    );

    btn_debounce U_BTN_DB (
        .clk  (clk),
        .reset(rst),
        .i_btn(btnR),
        .o_btn(w_dht11_start)
    );

    tick_gen_us U_TICK_GEN (
        .clk    (clk),
        .rst    (rst),
        // .enable(w_enable),
        // .clear(w_clear),
        .us_tick(w_us_tick)
    );
endmodule

module tick_gen_us (
    input      clk,
    input      rst,
    // input      enable,
    // input      clear,
    output reg us_tick
);

    // 1us
    parameter F_COUNT = 100;
    reg [$clog2(F_COUNT) - 1 : 0] count_reg;

    always @(posedge clk, posedge rst) begin
        // if (rst || clear) begin
        if (rst) begin
            count_reg <= 0;
            us_tick   <= 1'b0;
        end else begin
            us_tick   <= 1'b0;

            // if (enable) begin
            count_reg <= count_reg + 1;
            if (count_reg == F_COUNT - 1) begin
                count_reg <= 0;
                us_tick   <= 1'b1;
            end
            // else begin 
            //     us_tick <= 1'b0;
            // end
            // end
        end
    end
endmodule
