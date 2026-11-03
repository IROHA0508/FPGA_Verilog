
`timescale 1ns / 1ps

module ascii_sender(
    input         clk,
    input         rst,
    input         done,
    input         vaild,
    input  [1:0]  data_type,
    input  [39:0] input_data,
    input         fifo_full,
    output reg [7:0] fifo_data,
    output        push,
    output        ready,
    output        sender_busy
);

    localparam [1:0] TYPE_STOPWATCH = 2'b00,
                     TYPE_WATCH     = 2'b01,
                     TYPE_SR04      = 2'b10,
                     TYPE_DHT11     = 2'b11;

    localparam [2:0] IDLE          = 3'd0,
                     PREPARE       = 3'd1,
                     CONVERT_START = 3'd2,
                     CONVERT_WAIT  = 3'd3,
                     SEND          = 3'd4;

    reg [2:0] state;
    reg [39:0] data_reg;
    reg [1:0] type_reg;
    reg error_reg;

    reg [4:0] char_index;
    reg [4:0] last_index;
    reg [1:0] field_index;

    reg [63:0] ascii_0, ascii_1, ascii_2, ascii_3;
    reg [23:0] convert_binary;
    wire [63:0] convert_ascii;
    wire convert_done;


    // Binary -> ASCII Converter
    bin24_to_ascii8 U_BINARY_TO_ASCII (
        .clk         (clk),
        .rst         (rst),
        .start       (state == CONVERT_START),
        .binary_data (convert_binary),
        .ascii_data  (convert_ascii),
        .busy        (),
        .done        (convert_done)
    );


    // Binary Data
    // watch/stopwatch_data 24bit
    wire [4:0] hour   = data_reg[23:19];
    wire [5:0] minute = data_reg[18:13];
    wire [5:0] second = data_reg[12:7];
    wire [6:0] msec   = data_reg[6:0];

    // SR04 data 24bit
    wire [23:0] distance = data_reg[23:0];

    // DHT11 Data 40-bit

    // {습도 정수, 습도 소수, 온도 정수, 온도 소수, 체크섬}
    // 체크섬: data_reg[7:0]
    // 검사 결과는 외부에서 vaild로 전달

    wire [31:0] dht_payload = data_reg[39:8];

    wire [7:0] humid_int = dht_payload[31:24];
    wire [7:0] humid_dec = dht_payload[23:16];
    wire [7:0] temp_int  = dht_payload[15:8];
    wire [7:0] temp_dec  = dht_payload[7:0];


    // Output Control
    assign ready       = !rst && (state == IDLE);
    assign sender_busy = !rst && (state != IDLE);
    assign push        = !rst && (state == SEND) && !fifo_full;


    // Binary Data Selection
    always @(*) begin
        convert_binary = 24'd0;

        case (type_reg)

            TYPE_STOPWATCH, TYPE_WATCH: begin
                case (field_index)
                    2'd0: convert_binary = {19'd0, hour};
                    2'd1: convert_binary = {18'd0, minute};
                    2'd2: convert_binary = {18'd0, second};
                    2'd3: convert_binary = {17'd0, msec};
                endcase
            end

            TYPE_SR04: begin
                convert_binary = distance;
            end

            TYPE_DHT11: begin
                case (field_index)
                    2'd0: convert_binary = {16'd0, humid_int};
                    2'd1: convert_binary = {16'd0, humid_dec};
                    2'd2: convert_binary = {16'd0, temp_int};
                    2'd3: convert_binary = {16'd0, temp_dec};
                endcase
            end

        endcase
    end


    

    // 6. FSM

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state       <= IDLE;
            data_reg    <= 40'd0;
            type_reg    <= TYPE_STOPWATCH;
            error_reg   <= 1'b0;
            char_index  <= 5'd0;
            last_index  <= 5'd0;
            field_index <= 2'd0;

            ascii_0 <= "00000000";
            ascii_1 <= "00000000";
            ascii_2 <= "00000000";
            ascii_3 <= "00000000";

        end else begin
            case (state)

                IDLE: begin
                    if (done) begin
                        data_reg <= input_data;
                        type_reg <= data_type;

                        error_reg <=
                            ((data_type == TYPE_SR04) ||
                             (data_type == TYPE_DHT11)) && !vaild;

                        char_index  <= 5'd0;
                        field_index <= 2'd0;
                        state <= PREPARE;
                    end
                end


                PREPARE: begin
                    if (error_reg) begin
                        last_index <= 5'd5;
                        state <= SEND;

                    end else begin
                        case (type_reg)

                            TYPE_STOPWATCH, TYPE_WATCH:
                                last_index <= 5'd12;

                            // SR04: 총 6문자 (0~5)
                            TYPE_SR04:
                                last_index <= 5'd7;

                            // DHT11: 총 19문자 (0~18)
                            TYPE_DHT11:
                                last_index <= 5'd20;

                        endcase

                        state <= CONVERT_START;
                    end
                end


                CONVERT_START: begin
                    state <= CONVERT_WAIT;
                end


                CONVERT_WAIT: begin
                    if (convert_done) begin

                        case (field_index)
                            2'd0: ascii_0 <= convert_ascii;
                            2'd1: ascii_1 <= convert_ascii;
                            2'd2: ascii_2 <= convert_ascii;
                            2'd3: ascii_3 <= convert_ascii;
                        endcase

                        if ((type_reg == TYPE_SR04) ||
                            (field_index == 2'd3)) begin

                            state <= SEND;

                        end else begin
                            field_index <= field_index + 1'b1;
                            state <= CONVERT_START;
                        end
                    end
                end


                SEND: begin
                    if (push) begin
                        if (char_index == last_index)
                            state <= IDLE;
                        else
                            char_index <= char_index + 1'b1;
                    end
                end


                default: state <= IDLE;

            endcase
        end
    end

    // ASCII Output Data
    always @(*) begin
        fifo_data = 8'h00;

        if (state == SEND) begin

            if (error_reg) begin
                case (char_index)
                    0, 1, 2, 3: fifo_data = "x";
                    4: fifo_data = 8'h0D;
                    5: fifo_data = 8'h0A;
                    default: fifo_data = 8'h00;
                endcase

            end else begin

                case (type_reg)

                    //--------------------------------
                    // WATCH / STOPWATCH
                    // HH:MM:SS:MS
                    // 총 11문자
                    //--------------------------------

                    TYPE_STOPWATCH, TYPE_WATCH: begin
                        case (char_index)

                            0: fifo_data = ascii_0[15:8];
                            1: fifo_data = ascii_0[7:0];

                            2, 5, 8: fifo_data = ":";

                            3: fifo_data = ascii_1[15:8];
                            4: fifo_data = ascii_1[7:0];

                            6: fifo_data = ascii_2[15:8];
                            7: fifo_data = ascii_2[7:0];

                            9:  fifo_data = ascii_3[15:8];
                            10: fifo_data = ascii_3[7:0];

                            11: fifo_data = 8'h0D;
                            12: fifo_data = 8'h0A;

                            default: fifo_data = 8'h00;

                        endcase
                    end


                    //--------------------------------
                    // SR04
                    // 숫자 4자리 + cm
                    // 총 6문자
                    //--------------------------------

                    TYPE_SR04: begin
                        case (char_index)

                            0: fifo_data = ascii_0[31:24];
                            1: fifo_data = ascii_0[23:16];
                            2: fifo_data = ascii_0[15:8];
                            3: fifo_data = ascii_0[7:0];

                            4: fifo_data = "c";
                            5: fifo_data = "m";

                            6: fifo_data = 8'h0D;
                            7: fifo_data = 8'h0A;

                            default: fifo_data = 8'h00;

                        endcase
                    end


                    //--------------------------------
                    // DHT11
                    // H=000.00% T=000.00C
                    // 총 19문자
                    //--------------------------------

                    TYPE_DHT11: begin
                        case (char_index)

                            0: fifo_data = "H";
                            1, 11: fifo_data = "=";

                            // 습도 정수
                            2: fifo_data = ascii_0[23:16];
                            3: fifo_data = ascii_0[15:8];
                            4: fifo_data = ascii_0[7:0];

                            // 소수점
                            5, 15: fifo_data = ".";

                            // 습도 소수
                            6: fifo_data = ascii_1[7:0];
                            7: fifo_data = "0";

                            // 습도 단위 및 공백
                            8: fifo_data = "%";
                            9: fifo_data = " ";

                            // 온도 표시
                            10: fifo_data = "T";

                            // 온도 정수
                            12: fifo_data = ascii_2[23:16];
                            13: fifo_data = ascii_2[15:8];
                            14: fifo_data = ascii_2[7:0];

                            // 온도 소수
                            16: fifo_data = ascii_3[7:0];
                            17: fifo_data = "0";

                            // 온도 단위
                            18: fifo_data = "C";

                            19: fifo_data = 8'h0D;
                            20: fifo_data = 8'h0A;

                            default: fifo_data = 8'h00;

                        endcase
                    end

                endcase
            end
        end
    end

endmodule
