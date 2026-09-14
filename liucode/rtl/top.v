`timescale 1ns / 1ps

module top #(
    parameter IMEM_FILE = "uart_sort_demo.mem",
    // "pipeline" is the integrated board default; use "single_cycle" to
    // synthesize the original core with the same display and pinout.
    parameter CPU_TYPE = "pipeline",
    parameter integer CPU_STEP_CYCLES = 1,
    parameter integer SCAN_CYCLES = 100000,
    parameter integer UART_CLOCK_FREQ_HZ = 100000000,
    parameter integer UART_BAUD_RATE = 115200,
    parameter integer DISPLAY_HOLD_CYCLES = 100000000,
    parameter integer RESET_RELEASE_CYCLES = 2000000,
    parameter integer DISPLAY_IDLE_CPU_MONITOR = 0
)(
    input wire I_clk,
    input wire I_rst_n,
    input wire I_rs232_rxd,
    output wire O_rs232_txd,
    output wire [6:0] O_led,
    output wire [6:0] O_led_high,
    output wire [7:0] O_px,
    output wire [1:0] O_dp
);
    // The mechanical S8 key can bounce for milliseconds.  Synchronize it and
    // require a continuous high interval before releasing reset, otherwise a
    // bounce can restart the UART in the middle of the first READY byte.
    (* ASYNC_REG = "TRUE" *) reg [1:0] reset_pipe = 2'b00;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) reset_pipe <= 2'b00;
        else          reset_pipe <= {reset_pipe[0], 1'b1};
    end

    localparam integer RESET_COUNT_WIDTH =
        (RESET_RELEASE_CYCLES <= 2) ? 1 : $clog2(RESET_RELEASE_CYCLES);
    reg [RESET_COUNT_WIDTH-1:0] reset_release_counter = 0;
    reg reset_n = 1'b0;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            reset_release_counter <= 0;
            reset_n <= 1'b0;
        end else if (!reset_pipe[1]) begin
            reset_release_counter <= 0;
            reset_n <= 1'b0;
        end else if (!reset_n) begin
            if (RESET_RELEASE_CYCLES <= 1 ||
                reset_release_counter == RESET_RELEASE_CYCLES - 1) begin
                reset_release_counter <= 0;
                reset_n <= 1'b1;
            end else begin
                reset_release_counter <= reset_release_counter + 1'b1;
            end
        end
    end
    wire [31:0] x31_value;
    wire [31:0] mmio_addr;
    wire [31:0] mmio_wdata;
    wire [31:0] mmio_rdata;
    wire        mmio_we;
    wire        mmio_re;
    wire        uart_rx_valid_debug;
    wire        uart_tx_busy_debug;
    wire [31:0] display_sequence_value;
    wire        display_sequence_active;

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
                .mmio_rdata(mmio_rdata),
                .mmio_addr(mmio_addr), .mmio_wdata(mmio_wdata),
                .mmio_we(mmio_we), .mmio_re(mmio_re),
                .x31_out(x31_value),
                .retire_valid(retire_valid_unused),
                .retire_pc(retire_pc_unused),
                .retire_instr(retire_instr_unused),
                .retire_ovf(), .ovf_out(),
                .int_req(1'b0), .int_en(1'b0), .mepc_out()
            );
        end else begin : gen_single_cycle_cpu
            assign mmio_addr  = 32'b0;
            assign mmio_wdata = 32'b0;
            assign mmio_we    = 1'b0;
            assign mmio_re    = 1'b0;
            RV32_CPU #(.IMEM_FILE(IMEM_FILE)) cpu (
                .clk(I_clk), .reset(!reset_n), .enable(cpu_enable),
                .x31_out(x31_value),
                .retire_ovf(), .ovf_out(),
                .int_req(1'b0), .int_en(1'b0), .mepc_out()
            );
        end
    endgenerate

    uart_mmio #(
        .CLOCK_FREQ_HZ(UART_CLOCK_FREQ_HZ),
        .BAUD_RATE(UART_BAUD_RATE)
    ) uart (
        .clk(I_clk), .reset(!reset_n),
        .uart_rx(I_rs232_rxd), .uart_tx(O_rs232_txd),
        .bus_addr(mmio_addr), .bus_wdata(mmio_wdata),
        .bus_write(mmio_we), .bus_read(mmio_re),
        .bus_rdata(mmio_rdata),
        .rx_valid_debug(uart_rx_valid_debug),
        .tx_busy_debug(uart_tx_busy_debug)
    );

    display_sequence_mmio #(
        .HOLD_CYCLES(DISPLAY_HOLD_CYCLES),
        .MAX_ENTRIES(17)
    ) display_sequence (
        .clk(I_clk), .reset(!reset_n),
        .bus_addr(mmio_addr), .bus_wdata(mmio_wdata),
        .bus_write(mmio_we),
        .display_value(display_sequence_value),
        .active(display_sequence_active)
    );

    // In the UART demo the CPU spins in a polling loop while idle.  Showing
    // its per-instruction monitor here would blend rapidly changing 1/2/etc.
    // Keep the display at zero until the sorted playback queue starts.
    wire [31:0] idle_display_value = DISPLAY_IDLE_CPU_MONITOR
                                      ? x31_value : 32'b0;
    wire [31:0] seven_segment_value = display_sequence_active
                                       ? display_sequence_value
                                       : idle_display_value;

    LCD_controller #(.SCAN_CYCLES(SCAN_CYCLES)) lcd (
        .I_clk(I_clk), .I_rst_n(reset_n), .I_data(seven_segment_value),
        .O_led(O_led), .O_led_high(O_led_high),
        .O_px(O_px), .O_dp(O_dp)
    );
endmodule
