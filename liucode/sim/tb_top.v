`timescale 1ns / 1ps

module tb_top;
    reg clk = 0;
    reg rst_n = 0;
    wire [6:0] led;
    wire [6:0] led_high;
    wire [7:0] px;
    wire [1:0] dp;
    integer n;
    integer seen;

    always #5 clk = ~clk;

    top #(
        .IMEM_FILE("inst26_test.mem"),
        .CPU_STEP_CYCLES(200),
        .SCAN_CYCLES(12)
    ) dut (
        .I_clk(clk), .I_rst_n(rst_n),
        .O_led(led), .O_led_high(led_high),
        .O_px(px), .O_dp(dp)
    );

    initial begin
        repeat (4) @(negedge clk);
        #1 rst_n = 1;

        // The first ADDI produces 7. It remains stable long enough for the
        // real display pipeline to convert and scan it before later results.
        wait (dut.x31_value == 32'd7);
        repeat (80) @(negedge clk);
        seen = 0;
        for (n = 0; n < 100; n = n + 1) begin
            @(negedge clk);
            if (px == 8'b00000001 && led == 7'b1110000)
                seen = seen + 1;
        end
        if (seen == 0)
            $fatal(1, "intermediate result 7 was not displayed");

        // Allow the complete program to reach its terminal hold instruction.
        repeat (12000) @(negedge clk);
        repeat (300) @(negedge clk);
        seen = 0;
        for (n = 0; n < 200; n = n + 1) begin
            @(negedge clk);
            if (dut.x31_value !== 32'd3)
                $fatal(1, "top-level x31 expected 3");
            if (dp !== 0)
                $fatal(1, "decimal points must remain off");
            if (px !== 0) begin
                if (px !== 8'b00000001 || led !== 7'b1111001)
                    $fatal(1, "expected only rightmost digit 3, px=%h led=%b", px, led);
                if (led_high !== 0)
                    $fatal(1, "left segment bank must be blank");
                seen = seen + 1;
            end
        end
        if (seen == 0)
            $fatal(1, "no visible digit was scanned");

        #2 rst_n = 0;
        #1;
        if (dut.x31_value !== 0 || px !== 0)
            $fatal(1, "reset did not clear CPU/display outputs");

        $display("PASS tb_top: display changed during execution and finished at 3");
        $finish;
    end

    initial begin
        #500000;
        $fatal(1, "tb_top timeout");
    end
endmodule
