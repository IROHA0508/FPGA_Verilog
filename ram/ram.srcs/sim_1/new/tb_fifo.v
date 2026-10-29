`timescale 1ns / 1ps

module tb_fifo ();
    reg clk, rst, push, pop;
    reg  [7:0] push_data;
    wire [7:0] pop_data;
    wire full, empty;
    integer i;

    // Test
    parameter DEPTH = 4;
    reg [7:0] compare_buffer[0 : DEPTH - 1];
    reg [1:0] push_count, pop_count;
    integer pass_count;
    integer fail_count;

    fifo #(
        .DEPTH(DEPTH)
    ) dut (
        .clk     (clk),
        .rst     (rst),
        .push    (push),
        .pop     (pop),
        .pushdata(push_data),
        .popdata (pop_data),
        .full    (full),
        .empty   (empty)
    );

    always #5 clk = ~clk;

    initial begin
        clk        = 0;
        rst        = 1;
        push       = 0;
        push_data  = 0;
        pop        = 0;
        i          = 0;
        pass_count = 0;
        fail_count = 0;
        push_count = 0;
        pop_count  = 0;

        @(negedge clk);
        @(negedge clk);

        // initial
        rst = 0;
        @(negedge clk);
        if (full == 0) begin
            $display("%t : pass full signal", $stime);
        end else begin
            $display("%t : fail full signal", $stime);
        end

        @(negedge clk);
        if (empty == 1) begin
            $display("%t : pass empty signal", $stime);
        end else begin
            $display("%t : fail empty signal", $stime);
        end


        // push only
        $display("***************PUSH ONLY***************");
        for (i = 0; i < 5; i = i + 1) begin
            @(negedge clk);
            push_data = 8'h0a + i;
            push = 1;
            $display("PUSH DATA : %d", push_data);
            // fill compare buffer
            if (!full) begin
                compare_buffer[push_count] = push_data;
                push_count = push_count + 1;
                $display("COMP BUF : %d \n", compare_buffer[i]);
            end
        end
        @(negedge clk);
        push = 1'b0;

        // pop only
        $display("***************POP ONLY***************");
        for (i = 0; i < 5; i = i + 1) begin
            @(negedge clk);
            pop = 1'b1;
            // pass fail test
            if (!empty) begin
                if (pop_data == compare_buffer[pop_count]) begin
                    $display("%t : pass pop data = %d, compare = %d", $time,
                             pop_data, compare_buffer[pop_count]);
                end else begin
                    $display("%t : fail pop data = %d, compare = %d", $time,
                             pop_data, compare_buffer[pop_count]);
                end
                pop_count = pop_count + 1;
            end
        end

        if (empty) begin
            $display("%t : pass empty signal", $time);
        end else begin
            $display("%t : fail empty signal", $time);
        end

        @(negedge clk);
        pop  = 1'b0;
        push = 1'b0;

        // push pop 5times
        $display("***************PUSH POP***************");
        for (i = 0; i < 5; i = i + 1) begin
            @(negedge clk);
            push = 1'b1;
            push_data = 8'h0f - i;
            if (!full) begin
                compare_buffer[push_count] = push_data;
                push_count = push_count + 1;
            end
            pop = 1'b1;
            // pass fail test
            if (!empty) begin
                if (pop_data == compare_buffer[pop_count]) begin
                    $display("%t : pass pop data = %d, compare = %d", $time,
                             pop_data, compare_buffer[pop_count]);
                end else begin
                    $display("%t : fail pop data = %d, compare = %d", $time,
                             pop_data, compare_buffer[pop_count]);
                end
                pop_count = pop_count + 1;
            end
        end

        #1000;
        // initialize
        @(negedge clk);
        push      = 0;
        pop       = 1;
        pop_count = pop_count + 1;
        @(negedge clk);
        pop = 0;
        @(negedge clk);
        $display("FULL : %d, EMPTY : %d", full, empty);

        // random test
        $display("***************RANDOM TEST START***************");
        for (i = 0; i < 256; i = i + 1) begin
            @(negedge clk);
            push = $random() % 2;
            pop = $random() % 2;
            push_data = $random() % 256;
            $display("PUSH DATA : ", push_data);

            // push 1
            if (push && ~full) begin
                compare_buffer[push_count] = push_data;
                push_count = push_count + 1;
            end

            // pop 1
            if (pop && ~empty) begin
                if (pop_data == compare_buffer[pop_count]) begin
                    pass_count = pass_count + 1;
                    $display("%t : pass pop data = %d, compare = %d", $time,
                             pop_data, compare_buffer[pop_count]);
                end else begin
                    fail_count = fail_count + 1;
                    $display("%t : fail pop data = %d, compare = %d", $time,
                             pop_data, compare_buffer[pop_count]);
                end
                pop_count = pop_count + 1;
            end
        end

        #10 $display("*** RANDOM TEST RESULT ***");
        $display("total random test = %d", i);
        $display("pass count = %d", pass_count);
        $display("fail count = %d", fail_count);
        #10 #100;
        $finish;
    end
endmodule
