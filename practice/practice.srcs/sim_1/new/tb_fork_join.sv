`timescale 1ns / 1ps

module tb_fork_join();
    initial begin 
        #1 $display("%t : start fork - join_none", $time);

        fork
            #10 A_thread();
            #20 B_thread();
            #15 C_thread();
        join_none

        #10 $display("%t : end fork - join_none", $time);
    end

    task A_thread();
        $display("%t : A thread", $time);
    endtask
    
    task B_thread();
        $display("%t : B thread", $time);
    endtask

    task C_thread();
        $display("%t : C thread", $time);
    endtask
endmodule
