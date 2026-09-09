`timescale 1ns / 1ps

// CPU performance benchmark for the programs already present in programs/.
//
// The adapter below gives the single-cycle and pipelined cores one common
// retirement interface.  Select the implementation at the USER SETTING near
// the beginning of module tb_cpu_performance.

`ifndef PERF_CPU_ADAPTER
`define PERF_CPU_ADAPTER perf_rv32_cpu_adapter
`define PERF_BUILD_DEFAULT_ADAPTER
`endif

`ifdef PERF_BUILD_DEFAULT_ADAPTER
module perf_rv32_cpu_adapter #(
    parameter IMEM_FILE = "inst26_test.mem",
    parameter CPU_TYPE  = "single_cycle"
)(
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,
    output wire [31:0] result,
    output wire        retire_valid,
    output wire [31:0] retire_pc,
    output wire [31:0] retire_instr
);
    generate
        if (CPU_TYPE == "pipeline") begin : gen_pipeline
            RV32_Pipeline #(.IMEM_FILE(IMEM_FILE)) u_cpu (
                .clk(clk), .reset(reset), .enable(enable),
                .x31_out(result),
                .retire_valid(retire_valid),
                .retire_pc(retire_pc),
                .retire_instr(retire_instr)
            );
        end else begin : gen_single_cycle
            RV32_CPU #(.IMEM_FILE(IMEM_FILE)) u_cpu (
                .clk(clk), .reset(reset), .enable(enable),
                .x31_out(result)
            );
            assign retire_valid = enable && !reset;
            assign retire_pc    = u_cpu.pc;
            assign retire_instr = u_cpu.instr;
        end
    endgenerate
endmodule
`endif

module cpu_perf_case #(
    parameter IMEM_FILE       = "inst26_test.mem",
    parameter TEST_NAME       = "inst26",
    parameter CPU_TYPE        = "single_cycle",
    parameter [31:0] EXPECTED = 32'd0,
    parameter integer CLOCK_FREQ_HZ = 100_000_000,
    parameter integer MAX_CYCLES    = 100_000,
    parameter [31:0] END_INSTR      = 32'h00000063
)(
    input  wire        clk,
    input  wire        reset,
    output reg         done,
    output reg  [63:0] measured_cycles,
    output reg  [63:0] retired_instructions
);
    wire [31:0] result;
    wire        retire_valid;
    wire [31:0] retire_pc;
    wire [31:0] retire_instr;
    integer cycle_count;
    integer instruction_count;
    real cpi;
    real clock_period_us;
    real cpu_time_us;
    real cpu_time_formula_us;
    real cpu_time_error_us;

    `PERF_CPU_ADAPTER #(
        .IMEM_FILE(IMEM_FILE),
        .CPU_TYPE(CPU_TYPE)
    ) dut (
        .clk(clk),
        .reset(reset),
        .enable(1'b1),
        .result(result),
        .retire_valid(retire_valid),
        .retire_pc(retire_pc),
        .retire_instr(retire_instr)
    );

    initial begin
        done = 1'b0;
        measured_cycles = 64'd0;
        retired_instructions = 64'd0;
        cycle_count = 0;
        instruction_count = 0;
    end

    always @(posedge clk) begin
        if (reset) begin
            done = 1'b0;
            measured_cycles = 64'd0;
            retired_instructions = 64'd0;
            cycle_count = 0;
            instruction_count = 0;
        end else if (!done) begin
            // END_INSTR is a benchmark sentinel, not useful program work.  At
            // its retirement, cycle_count already contains all cycles spent on
            // useful work (including pipeline fill, stalls and flushes).
            if (retire_valid && retire_instr === END_INSTR) begin
                if (result !== EXPECTED)
                    $fatal(1,
                        "PERF FAIL %-12s: expected result %0d, got %0d at PC 0x%08h",
                        TEST_NAME, EXPECTED, result, retire_pc);
                if (instruction_count == 0)
                    $fatal(1, "PERF FAIL %-12s: no instruction retired", TEST_NAME);

                measured_cycles = cycle_count;
                retired_instructions = instruction_count;
                cpi = $itor(cycle_count) / $itor(instruction_count);
                clock_period_us = 1000000.0 / CLOCK_FREQ_HZ;
                cpu_time_us = $itor(cycle_count) * clock_period_us;

                // Check the standard CPU performance equation:
                // T_cpu = IC * CPI * T_clk.
                cpu_time_formula_us = $itor(instruction_count) * cpi *
                                      clock_period_us;
                cpu_time_error_us = cpu_time_us - cpu_time_formula_us;
                if (cpu_time_error_us < 0.0)
                    cpu_time_error_us = -cpu_time_error_us;
                if (cpu_time_error_us > 0.000000001)
                    $fatal(1,
                        "PERF FORMULA FAIL %-12s: T_cpu=%0.9f us, IC*CPI*T_clk=%0.9f us",
                        TEST_NAME, cpu_time_us, cpu_time_formula_us);
                done = 1'b1;

                $display(
                    "PERF,%s,CPI=%0.6f,CPU_time_us=%0.6f,clock_cycles=%0d,IC=%0d,T_clk_ns=%0.6f,formula_check=PASS",
                    TEST_NAME, cpi, cpu_time_us, cycle_count,
                    instruction_count, clock_period_us * 1000.0);
            end else begin
                cycle_count = cycle_count + 1;
                if (retire_valid)
                    instruction_count = instruction_count + 1;
                if (cycle_count >= MAX_CYCLES)
                    $fatal(1,
                        "PERF TIMEOUT %-12s: %0d cycles, last retire PC=0x%08h instr=0x%08h",
                        TEST_NAME, cycle_count, retire_pc, retire_instr);
            end
        end
    end
endmodule

module tb_cpu_performance;
    // ===== USER SETTING =====
    // Change only this value to "single_cycle" or "pipeline".
    localparam CPU_TYPE = "pipeline";

    // Replace either frequency with a post-synthesis value for a timing-aware
    // comparison.  The defaults compare cycle count and CPI at the board clock.
    localparam integer SINGLE_CYCLE_CLOCK_FREQ_HZ = 100_000_000;
    localparam integer PIPELINE_CLOCK_FREQ_HZ     = 100_000_000;
    localparam integer CLOCK_FREQ_HZ =
        (CPU_TYPE == "pipeline") ? PIPELINE_CLOCK_FREQ_HZ
                                  : SINGLE_CYCLE_CLOCK_FREQ_HZ;
    localparam real CLOCK_HALF_NS = 500000000.0 / CLOCK_FREQ_HZ;

    reg clk;
    reg reset;
    wire done_inst26;
    wire done_raw;
    wire done_loaduse;
    wire done_branch;
    wire done_sort;
    wire [63:0] cycles_inst26, instructions_inst26;
    wire [63:0] cycles_raw, instructions_raw;
    wire [63:0] cycles_loaduse, instructions_loaduse;
    wire [63:0] cycles_branch, instructions_branch;
    wire [63:0] cycles_sort, instructions_sort;
    integer total_cycles;
    integer total_instructions;
    real suite_cpi;
    real suite_cpu_time_us;
    real suite_cpu_time_formula_us;
    real suite_cpu_time_error_us;
    real clock_period_us;

    always #CLOCK_HALF_NS clk = ~clk;

    cpu_perf_case #(
        .IMEM_FILE("inst26_test.mem"), .TEST_NAME("inst26"),
        .EXPECTED(32'd3), .CPU_TYPE(CPU_TYPE),
        .CLOCK_FREQ_HZ(CLOCK_FREQ_HZ)
    ) perf_inst26 (
        .clk(clk), .reset(reset), .done(done_inst26),
        .measured_cycles(cycles_inst26),
        .retired_instructions(instructions_inst26)
    );

    cpu_perf_case #(
        .IMEM_FILE("raw_test.mem"), .TEST_NAME("raw"),
        .EXPECTED(32'd300), .CPU_TYPE(CPU_TYPE),
        .CLOCK_FREQ_HZ(CLOCK_FREQ_HZ)
    ) perf_raw (
        .clk(clk), .reset(reset), .done(done_raw),
        .measured_cycles(cycles_raw),
        .retired_instructions(instructions_raw)
    );

    cpu_perf_case #(
        .IMEM_FILE("loaduse_test.mem"), .TEST_NAME("loaduse"),
        .EXPECTED(32'd17), .CPU_TYPE(CPU_TYPE),
        .CLOCK_FREQ_HZ(CLOCK_FREQ_HZ)
    ) perf_loaduse (
        .clk(clk), .reset(reset), .done(done_loaduse),
        .measured_cycles(cycles_loaduse),
        .retired_instructions(instructions_loaduse)
    );

    cpu_perf_case #(
        .IMEM_FILE("branch_test.mem"), .TEST_NAME("branch"),
        .EXPECTED(32'd55), .CPU_TYPE(CPU_TYPE),
        .CLOCK_FREQ_HZ(CLOCK_FREQ_HZ)
    ) perf_branch (
        .clk(clk), .reset(reset), .done(done_branch),
        .measured_cycles(cycles_branch),
        .retired_instructions(instructions_branch)
    );

    cpu_perf_case #(
        .IMEM_FILE("sort16.mem"), .TEST_NAME("sort16"),
        .EXPECTED(32'd15), .CPU_TYPE(CPU_TYPE),
        .CLOCK_FREQ_HZ(CLOCK_FREQ_HZ)
    ) perf_sort (
        .clk(clk), .reset(reset), .done(done_sort),
        .measured_cycles(cycles_sort),
        .retired_instructions(instructions_sort)
    );

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        if ((CPU_TYPE != "single_cycle") && (CPU_TYPE != "pipeline"))
            $fatal(1, "CPU_TYPE must be single_cycle or pipeline");
        $display("PERF CPU_TYPE=%s CLOCK_FREQ_HZ=%0d", CPU_TYPE, CLOCK_FREQ_HZ);
        repeat (4) @(negedge clk);
        reset = 1'b0;

        wait (done_inst26 && done_raw && done_loaduse &&
              done_branch && done_sort);
        #1;

        // Treat the five programs as a sequential benchmark suite.  This is a
        // weighted aggregate, unlike averaging the five CPI values directly.
        total_cycles = cycles_inst26 + cycles_raw + cycles_loaduse +
                       cycles_branch + cycles_sort;
        total_instructions = instructions_inst26 + instructions_raw +
                             instructions_loaduse + instructions_branch +
                             instructions_sort;
        suite_cpi = $itor(total_cycles) / $itor(total_instructions);
        clock_period_us = 1000000.0 / CLOCK_FREQ_HZ;
        suite_cpu_time_us = $itor(total_cycles) * clock_period_us;
        suite_cpu_time_formula_us = $itor(total_instructions) * suite_cpi *
                                    clock_period_us;
        suite_cpu_time_error_us = suite_cpu_time_us -
                                  suite_cpu_time_formula_us;
        if (suite_cpu_time_error_us < 0.0)
            suite_cpu_time_error_us = -suite_cpu_time_error_us;
        if (suite_cpu_time_error_us > 0.000000001)
            $fatal(1,
                "PERF FORMULA FAIL TOTAL: T_cpu=%0.9f us, IC*CPI*T_clk=%0.9f us",
                suite_cpu_time_us, suite_cpu_time_formula_us);

        $display(
            "PERF,TOTAL,CPI=%0.6f,CPU_time_us=%0.6f,clock_cycles=%0d,IC=%0d,T_clk_ns=%0.6f,formula_check=PASS",
            suite_cpi, suite_cpu_time_us, total_cycles,
            total_instructions, clock_period_us * 1000.0);
        $display("PASS tb_cpu_performance");
        $finish;
    end

    initial begin
        #2000000;
        $fatal(1, "tb_cpu_performance global timeout");
    end
endmodule
