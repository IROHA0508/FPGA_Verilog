`timescale 1ns / 1ps

module fifo_sv (
    input  logic       clk,
    input  logic       rst,
    input  logic [7:0] push_data,
    input  logic       push,
    input  logic       pop,
    output logic [7:0] pop_data,
    output logic       full,
    output logic       empty
);
    logic [1:0] waddr, raddr;

    register_file U_REG_FILE (
        // 이미 정의된 것들을 한번에 가져옴
        .*,
        .waddr    (waddr),
        .raddr    (raddr),
        .w_enable (push && ~full)
    );

    control_unit U_CNTL_UNIT (
        .*,
        .wptr (waddr),
        .rptr (raddr)
    );
endmodule

module register_file (
    input  logic       clk,
    input  logic [1:0] waddr,
    input  logic [1:0] raddr,
    input  logic [7:0] push_data,
    input  logic       w_enable,
    output logic [7:0] pop_data
);
    logic [7:0] ram[0:3];

    always_ff @(posedge clk) begin
        if (w_enable) ram[waddr] <= push_data;
    end

    assign pop_data = ram[raddr];
endmodule

module control_unit (
    input  logic       clk,
    input  logic       rst,
    input  logic       push,
    input  logic       pop,
    output logic [1:0] wptr,
    output logic [1:0] rptr,
    output logic       full,
    output logic       empty
);
    logic [1:0] wptr_next, rptr_next;
    logic full_next;
    logic empty_next;

    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            wptr  <= 2'b00;
            rptr  <= 2'b00;
            full  <= 1'b0;
            empty <= 1'b1;
        end else begin
            wptr  <= wptr_next;
            rptr  <= rptr_next;
            full  <= full_next;
            empty <= empty_next;
        end
    end

    always_comb begin
        full_next  = full;
        empty_next = empty;
        wptr_next  = wptr;
        rptr_next  = rptr;

        case ({
            push, pop
        })
            2'b01: begin  // pop
                if (!empty) begin
                    rptr_next = rptr + 1;
                    full_next = 1'b0;
                    if (rptr_next == wptr) empty_next = 1'b1;
                end
            end
            2'b10: begin  // push
                if (!full) begin
                    wptr_next  = wptr + 1;
                    empty_next = 1'b0;
                    if (wptr_next == rptr) full_next = 1'b1;
                end
            end
            2'b11: begin  // push + pop
                if (full) begin  // 가득 참: pop만
                    rptr_next = rptr + 1;
                    full_next = 1'b0;
                end else if (empty) begin  // 비어 있음: push만
                    wptr_next  = wptr + 1;
                    empty_next = 1'b0;
                end else begin
                    wptr_next = wptr + 1;
                    rptr_next = rptr + 1;
                end
            end
            default: ;
        endcase
    end
endmodule
