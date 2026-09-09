`timescale 1ns / 1ps

module top #(
    parameter IMEM_FILE = "inst26_test.mem",
    // "pipeline" is the integrated board default; use "single_cycle" to
    // synthesize the original core with the same display and pinout.
    parameter CPU_TYPE = "pipeline",
    parameter integer CPU_STEP_CYCLES = 100000000,
    parameter integer SCAN_CYCLES = 100000
)(
    input wire I_clk,
    input wire I_rst_n,
    output wire [6:0] O_led,
    output wire [6:0] O_led_high,
    output wire [7:0] O_px,
    output wire [1:0] O_dp
);
    // Asynchronous assertion and synchronous release for the active-low key.
    (* ASYNC_REG = "TRUE" *) reg [1:0] reset_pipe = 2'b00;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) reset_pipe <= 2'b00;
        else          reset_pipe <= {reset_pipe[0], 1'b1};
    end

    wire reset_n = reset_pipe[1];
    wire [31:0] x31_value;

    // Keep the display at 100 MHz, but retire one CPU instruction per pulse.
    // 5,000,000 clocks at 100 MHz = 50 ms per instruction by default.
    localparam integer STEP_COUNT_WIDTH =
        (CPU_STEP_CYCLES <= 2) ? 1 : $clog2(CPU_STEP_CYCLES);
    reg [STEP_COUNT_WIDTH-1:0] cpu_step_counter = 0;
    wire cpu_enable = (CPU_STEP_CYCLES <= 1)
                    ? 1'b1 : (cpu_step_counter == CPU_STEP_CYCLES - 1);
    always @(posedge I_clk or negedge reset_n) begin
        if (!reset_n)
            cpu_step_counter <= 0;
        else if (CPU_STEP_CYCLES <= 1 || cpu_enable)
            cpu_step_counter <= 0;
        else
            cpu_step_counter <= cpu_step_counter + 1'b1;
    end

    generate
        if (CPU_TYPE == "pipeline") begin : gen_pipeline_cpu
            wire retire_valid_unused;
            wire [31:0] retire_pc_unused;
            wire [31:0] retire_instr_unused;
            RV32_Pipeline #(.IMEM_FILE(IMEM_FILE)) cpu (
                .clk(I_clk), .reset(!reset_n), .enable(cpu_enable),
                .x31_out(x31_value),
                .retire_valid(retire_valid_unused),
                .retire_pc(retire_pc_unused),
                .retire_instr(retire_instr_unused)
            );
        end else begin : gen_single_cycle_cpu
            RV32_CPU #(.IMEM_FILE(IMEM_FILE)) cpu (
                .clk(I_clk), .reset(!reset_n), .enable(cpu_enable),
                .x31_out(x31_value)
            );
        end
    endgenerate

    LCD_controller #(.SCAN_CYCLES(SCAN_CYCLES)) lcd (
        .I_clk(I_clk), .I_rst_n(reset_n), .I_data(x31_value),
        .O_led(O_led), .O_led_high(O_led_high),
        .O_px(O_px), .O_dp(O_dp)
    );
endmodule
