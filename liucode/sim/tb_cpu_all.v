`timescale 1ns / 1ps

module tb_cpu_all;
    reg clk = 0;
    reg reset = 1;
    wire [31:0] out_inst26;
    wire [31:0] out_raw;
    wire [31:0] out_loaduse;
    wire [31:0] out_branch;
    wire [31:0] out_sort;
    integer i;

    always #5 clk = ~clk;

    RV32_CPU #(.IMEM_FILE("inst26_test.mem")) cpu_inst26 (
        .clk(clk), .reset(reset), .enable(1'b1), .x31_out(out_inst26)
    );
    RV32_CPU #(.IMEM_FILE("raw_test.mem")) cpu_raw (
        .clk(clk), .reset(reset), .enable(1'b1), .x31_out(out_raw)
    );
    RV32_CPU #(.IMEM_FILE("loaduse_test.mem")) cpu_loaduse (
        .clk(clk), .reset(reset), .enable(1'b1), .x31_out(out_loaduse)
    );
    RV32_CPU #(.IMEM_FILE("branch_test.mem")) cpu_branch (
        .clk(clk), .reset(reset), .enable(1'b1), .x31_out(out_branch)
    );
    RV32_CPU #(.IMEM_FILE("sort16.mem")) cpu_sort (
        .clk(clk), .reset(reset), .enable(1'b1), .x31_out(out_sort)
    );

    initial begin
        repeat (4) @(negedge clk);
        reset = 0;
        repeat (1200) @(negedge clk);

        if (out_inst26 !== 32'd3)   $fatal(1, "inst26 x31 expected 3, got %0d", out_inst26);
        if (out_raw !== 32'd300)    $fatal(1, "raw x31 expected 300, got %0d", out_raw);
        if (out_loaduse !== 32'd17) $fatal(1, "loaduse x31 expected 17, got %0d", out_loaduse);
        if (out_branch !== 32'd55)  $fatal(1, "branch x31 expected 55, got %0d", out_branch);
        if (out_sort !== 32'd15)    $fatal(1, "sort16 x31 expected 15, got %0d", out_sort);

        if (cpu_inst26.u_regfile.regs[4] !== 0 ||
            cpu_inst26.u_regfile.regs[8] !== 30 ||
            cpu_inst26.u_regfile.regs[9] !== 3 ||
            cpu_inst26.u_regfile.regs[10] !== 42 ||
            cpu_inst26.u_dmem.ram[0] !== 66 ||
            cpu_inst26.u_dmem.ram[1] !== 32'hffffffbe)
            $fatal(1, "inst26 detailed result mismatch");

        for (i = 0; i < 16; i = i + 1)
            if (cpu_sort.u_dmem.ram[i] !== i)
                $fatal(1, "sort16 memory mismatch at %0d", i);

        $display("PASS tb_cpu_all: x31 = 3, 300, 17, 55, 15; CPU state checks passed");
        $finish;
    end

    // Check that x31 follows individual retired instructions, not only the
    // final program result. Values correspond to the first inst26 operations.
    initial begin
        wait (reset == 0);
        @(negedge clk); if (out_inst26 !== 32'd7) $fatal(1, "result monitor missed addi x1=7");
        @(negedge clk); if (out_inst26 !== 32'd7) $fatal(1, "result monitor missed addi x2=7");
        @(negedge clk); if (out_inst26 !== 32'd9) $fatal(1, "result monitor missed addi x3=9");
        @(negedge clk); if (out_inst26 !== 32'd1) $fatal(1, "taken BEQ must display 1");
    end

    initial begin
        #200000;
        $fatal(1, "tb_cpu_all timeout");
    end
endmodule
