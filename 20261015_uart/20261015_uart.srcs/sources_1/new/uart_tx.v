`timescale 1ns / 1ps

// module uart(
//     input clk,
//     input rst,
//     input btnR,
//     output led,     // tx busy
//     output tx
//     );

//     wire w_b_tick, w_tx_start;

//     uart_tx U_UART_TX(
//         .clk(clk),
//         .rst(rst),
//         .tx_start(w_tx_start),
//         .tx_data(8'h30),
//         .b_tick(w_b_tick),
//         .tx(tx),
//         .tx_busy(led)
//     );

//     baud_tick_gen U_BAUD_TICK_GEN (
//         .clk(clk),
//         .rst(rst),
//         .b_tick(w_b_tick)
//     );

//     btn_debounce U_BD_TX_START(
//         .clk(clk),
//         .reset(rst),
//         .i_btn(btnR),
//         .o_btn(w_tx_start)
//     );

// endmodule

// uart_tx ver1 (basic)
// module uart_tx(
//     input clk,
//     input rst,
//     input tx_start,
//     input [7:0] tx_data,
//     input b_tick,
//     output tx,
//     output tx_busy
//     );

//     localparam IDLE = 0, START = 1,STOP = 10; 
//     localparam BIT0 = 2, BIT1 = 3, BIT2 = 4, BIT3 = 5, BIT4 = 6, BIT5 = 7, BIT6 = 8, BIT7 = 9;
//     localparam WAIT = 11;

//     reg [3:0] c_state, n_state;
//     reg tx_reg, tx_next;
//     reg tx_busy_reg, tx_busy_next;

//     // assign
//     assign tx = tx_reg;
//     assign tx_busy = tx_busy_reg;

//     // state SL
//     always @(posedge clk, posedge rst) begin 
//         if (rst) begin 
//             c_state <= IDLE;
//             tx_reg <= 1;
//             tx_busy_reg <= 0;
//         end else begin 
//             c_state <= n_state;
//             tx_reg <= tx_next;
//             tx_busy_reg <= tx_busy_next;
//         end
//     end

//     // next output CL
//     always @(*) begin 
//         n_state = c_state;
//         tx_next = tx_reg;
//         tx_busy_next = tx_busy_reg;
//         case(c_state)
//             IDLE : begin 
//                 tx_next = 1'b1;
//                 tx_busy_next = 1'b0;
//                 if (tx_start == 1) begin 
//                     // n_state = START;
//                     n_state = WAIT;
//                 end
//             end

//             WAIT : begin 
//                 if (b_tick == 1) begin 
//                     n_state = START;
//                 end
//             end

//             START : begin 
//                 tx_next = 1'b0;
//                 tx_busy_next = 1'b1;
//                 if (b_tick == 1) begin 
//                     n_state = BIT0;
//                 end
//             end

//             BIT0 : begin 
//                 tx_next = tx_data[0];
//                 if (b_tick == 1) begin 
//                     n_state = BIT1;
//                 end
//             end

//             BIT1 : begin 
//                 tx_next = tx_data[1];
//                 if (b_tick == 1) begin 
//                     n_state = BIT2;
//                 end
//             end

//             BIT2 : begin 
//                 tx_next = tx_data[2];
//                 if (b_tick == 1) begin 
//                     n_state = BIT3;
//                 end
//             end

//             BIT3 : begin 
//                 tx_next = tx_data[3];
//                 if (b_tick == 1) begin 
//                     n_state = BIT4;
//                 end
//             end

//             BIT4 : begin 
//                 tx_next = tx_data[4];
//                 if (b_tick == 1) begin 
//                     n_state = BIT5;
//                 end
//             end

//             BIT5 : begin 
//                 tx_next = tx_data[5];
//                 if (b_tick == 1) begin 
//                     n_state = BIT6;
//                 end
//             end

//             BIT6 : begin 
//                 tx_next = tx_data[6];
//                 if (b_tick == 1) begin 
//                     n_state = BIT7;
//                 end
//             end

//             BIT7 : begin 
//                 tx_next = tx_data[7];
//                 if (b_tick == 1) begin 
//                     n_state = STOP;
//                 end
//             end

//             STOP : begin 
//                 tx_next = 1'b1;
//                 if (b_tick == 1) begin 
//                     n_state = IDLE;
//                 end
//             end
//         endcase
//     end

// endmodule

// uart_tx ver2 (ADD Data State, Data_reg)
// module uart_tx(
//     input clk,
//     input rst,
//     input tx_start,
//     input [7:0] tx_data,
//     input b_tick,
//     output tx,
//     output tx_busy
//     );

//     // ADD : STOP, DELETE : BIT
//     localparam IDLE = 0, START = 1, DATA = 2, STOP = 3;
//     localparam WAIT = 4;

//     reg [2:0] c_state, n_state;
//     // ADD : bit count reg, data reg
//     reg [2:0] bit_count_reg, bit_count_next;
//     reg [7:0] data_reg, data_next;
    
//     reg tx_reg, tx_next;
//     reg tx_busy_reg, tx_busy_next;


//     // assign
//     assign tx = tx_reg;
//     assign tx_busy = tx_busy_reg;

//     // state SL
//     always @(posedge clk, posedge rst) begin 
//         if (rst) begin 
//             c_state <= IDLE;
//             tx_reg <= 1;
//             tx_busy_reg <= 0;

//             // ADD : reset bit count reg, data reg
//             bit_count_reg <= 0;
//             data_reg <= 0;

//         end else begin 
//             c_state <= n_state;
//             tx_reg <= tx_next;
//             tx_busy_reg <= tx_busy_next;

//             // ADD : bit count reg, data reg update
//             bit_count_reg <= bit_count_next;
//             data_reg <= data_next;
//         end
//     end

//     // next output CL
//     always @(*) begin 
//         n_state = c_state;
//         tx_next = tx_reg;
//         tx_busy_next = tx_busy_reg;

//         // ADD : init bit count next, data next
//         bit_count_next = bit_count_reg;
//         data_next = data_reg;
//         case(c_state)
//             IDLE : begin 
//                 tx_next = 1'b1;
//                 tx_busy_next = 1'b0;
//                 if (tx_start) begin 
//                     // n_state = START;
//                     n_state = WAIT;
                    
//                     // ADD : save tx_data to data_next;
//                     data_next = tx_data; 
//                 end
//             end

//             WAIT : begin 
//                 if (b_tick) begin 
//                     n_state = START;
//                 end
//             end

//             START : begin 
//                 tx_next = 1'b0;
//                 tx_busy_next = 1'b1;
//                 if (b_tick) begin 
//                     // ADD : init bit_count_next
//                     bit_count_next = 0;
//                     n_state = DATA;
//                 end
//             end

//             // DELETE : delete BIT cases 
//             // ADD : add Data cases
//             DATA : begin 
//                 // tx_next = data_reg[bit_count_reg];
                
//                 // ADD : Use Shift Register
//                 tx_next = data_reg[0];
//                 if (b_tick) begin 
//                     // Shift Register
//                     // data_next = data_reg >> 1;
//                     data_next = {1'b0, data_reg[7:1]};
//                     if (bit_count_reg == 7) begin 
//                         n_state = STOP;
//                     end else begin 
//                         bit_count_next = bit_count_reg + 1;
//                     end
//                 end
//             end

//             STOP : begin 
//                 tx_next = 1'b1;
//                 if (b_tick) begin 
//                     n_state = IDLE;
//                 end
//             end
//         endcase
//     end

// endmodule

// uart_tx ver3 (ADD Data State, Data_reg)
module uart_tx (
    input clk,
    input rst,
    input tx_start,
    input [7:0] tx_data,
    input b_tick,
    output tx,
    output tx_busy
);

    // state → often use localparam
    localparam IDLE = 0, START = 1, DATA = 2, STOP = 3;

    // 4 state → 2-bit
    reg [1:0] c_state, n_state;
    reg [2:0] bit_cnt_reg, bit_cnt_next;
    reg [3:0] b_tick_cnt_reg, b_tick_cnt_next;
    reg [7:0] data_reg, data_next;
    reg tx_reg, tx_next;
    reg tx_busy_reg, tx_busy_next;

    // Output connection
    assign tx = tx_reg;
    assign tx_busy = tx_busy_reg;

    // state & output SL (state register)
    always @(posedge clk, posedge rst) begin
        if (rst) begin
            c_state <= IDLE;
            bit_cnt_reg <= 3'b0;
            b_tick_cnt_reg <= 0;
            data_reg <= 8'h0;
            tx_reg <= 1'b1;  // pull-up
            tx_busy_reg <= 1'b0;
        end else begin
            c_state <= n_state;
            bit_cnt_reg <= bit_cnt_next;
            b_tick_cnt_reg <= b_tick_cnt_next;
            data_reg <= data_next;
            tx_reg <= tx_next;
            tx_busy_reg <= tx_busy_next;
        end
    end

    // next CL
    // tx, tx_busy → SL
    always @(*) begin
        // update
        n_state = c_state;
        bit_cnt_next = bit_cnt_reg;
        b_tick_cnt_next = b_tick_cnt_reg;
        data_next = data_reg;
        tx_next = tx_reg;
        tx_busy_next = tx_busy_reg;

        case (c_state)
            IDLE: begin
                // Moore output
                tx_next = 1'b1;
                tx_busy_next = 1'b0;
                // Next state
                //n_state = (tx_start == 1) ? START : IDLE;
                if (tx_start) begin
                    data_next = tx_data;
                    n_state   = START;

                    b_tick_cnt_next = 0;
                    bit_cnt_next = 0;
                end
            end

            // board tick의 stop으로 넣어버림?
            START: begin
                tx_next = 1'b0;
                tx_busy_next = 1'b1;
                if (b_tick) begin
                    if (b_tick_cnt_reg == 15) begin
                        b_tick_cnt_next = 0;
                        n_state = DATA;
                    end else begin 
                        b_tick_cnt_next = b_tick_cnt_reg + 1;
                    end
                end
            end

            DATA: begin
                // 보통 우변 reg 사용
                // 좌변은 무조건 next → multiple driven error 발생
                //tx_next = data_reg[bit_cnt_reg];
                tx_next = data_reg[0];  // 나가는 건 LSB만
                if (b_tick) begin
                    if (b_tick_cnt_reg == 15) begin
                        b_tick_cnt_next = 0;
                        if (bit_cnt_reg == 7) begin
                            n_state = STOP;
                        end else begin
                            bit_cnt_next = bit_cnt_reg + 1;
                            // shift register: data_next = data_reg >> 1;
                            data_next = {1'b0, data_reg[7:1]};
                        end
                    end else begin
                        b_tick_cnt_next = b_tick_cnt_reg + 1;
                    end
                end
            end

            STOP: begin
                tx_next = 1'b1;
                if (b_tick) begin
                    if (b_tick_cnt_reg == 15) n_state = IDLE;
                    else b_tick_cnt_next = b_tick_cnt_reg + 1;
                    
                end
            end
            default: begin
                n_state = IDLE;

                bit_cnt_next = 0;
                b_tick_cnt_next = 0;

            end
        endcase
    end

endmodule

module baud_tick_gen(
    input clk,
    input rst,
    output reg b_tick
    );

    //  100 Mhz -> 9600 Hz
    parameter F_COUNT = 100_000_000 / (9600 * 16);
    reg [$clog2(F_COUNT) - 1 : 0] count_reg;

    always @(posedge clk, posedge rst) begin 
        if (rst) begin 
            count_reg <= 0;
            b_tick <= 1'b0;
        end else begin
                count_reg <= count_reg + 1;
                b_tick <= 1'b0;
                if (count_reg == F_COUNT -1 ) begin
                    count_reg <= 0;
                    b_tick <= 1'b1; 
                end 
                // else begin 
                //     b_tick <= 1'b0;
                // end
        end
    end
endmodule
