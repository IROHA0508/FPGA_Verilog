`timescale 1ns / 1ps

module fifo #(
    parameter DEPTH = 4,
    ADDR_BIT_WIDTH = $clog2(DEPTH),
    DATA_BIT_WIDTH = 8
) (
    input                           clk,
    input                           rst,
    input                           push,
    input                           pop,
    input  [DATA_BIT_WIDTH - 1 : 0] pushdata,
    output [DATA_BIT_WIDTH - 1 : 0] popdata,
    output                          full,
    output                          empty
);
    wire [ADDR_BIT_WIDTH - 1 : 0] w_wptr, w_rptr;

    register_file #(
        .DEPTH         (DEPTH),
        .DATA_BIT_WIDTH(DATA_BIT_WIDTH)
    ) U_REG_FILE (
        .clk  (clk),
        .we   (~full && push),
        .wdata(pushdata),
        .waddr(w_wptr),
        .raddr(w_rptr),
        .rdata(popdata)
    );


    control_unit #(
        .ADDR_BIT_WIDTH(ADDR_BIT_WIDTH)
    ) U_CONTROL_UNIT (
        .clk  (clk),
        .rst  (rst),
        .push (push),
        .pop  (pop),
        .wptr (w_wptr),
        .rptr (w_rptr),
        .full (full),
        .empty(empty)
    );

endmodule

module register_file #(
    DEPTH = 4,
    ADDR_BIT_WIDTH = $clog2(DEPTH),
    DATA_BIT_WIDTH = 8
) (
    input                           clk,
    input                           we,
    input  [DATA_BIT_WIDTH - 1 : 0] wdata,
    input  [ADDR_BIT_WIDTH - 1 : 0] waddr,
    input  [ADDR_BIT_WIDTH - 1 : 0] raddr,
    output [DATA_BIT_WIDTH - 1 : 0] rdata
);
    // RAM
    reg [DATA_BIT_WIDTH - 1 : 0] register_file[0 : DEPTH - 1];

    // write SL
    always @(posedge clk) begin
        if (we) register_file[waddr] <= wdata;
    end

    // read CL
    assign rdata = register_file[raddr];
endmodule

module control_unit #(
    parameter ADDR_BIT_WIDTH = 2
) (
    input                           clk,
    input                           rst,
    input                           push,
    input                           pop,
    output [ADDR_BIT_WIDTH - 1 : 0] wptr,
    output [ADDR_BIT_WIDTH - 1 : 0] rptr,
    output                          full,
    output                          empty
);
    // reg [1:0] c_state, n_state;
    reg [ADDR_BIT_WIDTH -1 : 0] wptr_reg, wptr_next;
    reg [ADDR_BIT_WIDTH -1 : 0] rptr_reg, rptr_next;
    reg full_reg, full_next;
    reg empty_reg, empty_next;

    assign wptr  = wptr_reg;
    assign rptr  = rptr_reg;
    assign full  = full_reg;
    assign empty = empty_reg;

    always @(posedge clk, posedge rst) begin
        if (rst) begin
            full_reg  <= 1'b0;
            empty_reg <= 1'b1;
            wptr_reg  <= 0;
            rptr_reg  <= 0;
        end else begin
            full_reg  <= full_next;
            empty_reg <= empty_next;
            wptr_reg  <= wptr_next;
            rptr_reg  <= rptr_next;
        end
    end

    // next, output
    always @(*) begin
        full_next  = full_reg;
        empty_next = empty_reg;
        wptr_next  = wptr_reg;
        rptr_next  = rptr_reg;

        case ({
            push, pop
        })
            2'b10: begin
                if (!full_reg) begin
                    empty_next = 1'b0;
                    wptr_next  = wptr_reg + 1;
                    if (wptr_next == rptr_reg) begin
                        full_next = 1'b1;
                    end
                end
            end

            2'b01: begin
                if (!empty_reg) begin
                    full_next = 1'b0;
                    rptr_next = rptr_reg + 1;
                    if (rptr_next == wptr_reg) begin
                        empty_next = 1'b1;
                    end
                end
            end

            2'b11: begin
                if (full_reg) begin
                    rptr_next = rptr_reg + 1;
                    full_next = 1'b0;
                end else if (empty_reg) begin
                    wptr_next  = wptr_reg + 1;
                    empty_next = 1'b0;
                end else begin
                    wptr_next = wptr_reg + 1;
                    rptr_next = rptr_reg + 1;
                end
            end
        endcase
    end
endmodule
