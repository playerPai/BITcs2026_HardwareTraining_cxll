`timescale 1ns / 1ps

// Automatic end-to-end comparison:
// host text -> UART -> CPU parser -> bubble sort -> UART + display sequence.
module tb_cpu_uart;
    localparam integer CLOCK_FREQ_HZ = 100_000_000;
    localparam integer BAUD_RATE = 115_200;
    localparam integer CLKS_PER_BIT = CLOCK_FREQ_HZ / BAUD_RATE;
    localparam integer DISPLAY_HOLD_CYCLES = 200;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg rxd = 1'b1;
    wire txd;
    wire [6:0] led;
    wire [6:0] led_high;
    wire [7:0] px;
    wire [1:0] dp;
    reg [7:0] received;
    reg [7:0] input_bytes [0:10];
    reg [7:0] expected_banner [0:6];
    reg [7:0] expected_result [0:29];
    reg [31:0] expected_display [0:4];
    integer i;
    integer j;
    integer k;

    always #5 clk = ~clk;

    top #(
        .IMEM_FILE("uart_sort_demo.mem"),
        .CPU_TYPE("pipeline"),
        .CPU_STEP_CYCLES(1),
        .SCAN_CYCLES(12),
        .UART_CLOCK_FREQ_HZ(CLOCK_FREQ_HZ),
        .UART_BAUD_RATE(BAUD_RATE),
        .DISPLAY_HOLD_CYCLES(DISPLAY_HOLD_CYCLES),
        .RESET_RELEASE_CYCLES(2)
    ) dut (
        .I_clk(clk), .I_rst_n(rst_n),
        .I_rs232_rxd(rxd), .O_rs232_txd(txd),
        .O_led(led), .O_led_high(led_high), .O_px(px), .O_dp(dp)
    );

    task send_host_byte;
        input [7:0] value;
        integer bit_no;
        begin
            @(negedge clk);
            rxd = 1'b0;
            repeat (CLKS_PER_BIT) @(negedge clk);
            for (bit_no = 0; bit_no < 8; bit_no = bit_no + 1) begin
                rxd = value[bit_no];
                repeat (CLKS_PER_BIT) @(negedge clk);
            end
            rxd = 1'b1;
            repeat (CLKS_PER_BIT) @(negedge clk);
        end
    endtask

    task receive_device_byte;
        output [7:0] value;
        integer bit_no;
        begin
            @(negedge txd);
            repeat (CLKS_PER_BIT / 2) @(posedge clk);
            if (txd !== 1'b0)
                $fatal(1, "UART device start bit missing");
            for (bit_no = 0; bit_no < 8; bit_no = bit_no + 1) begin
                repeat (CLKS_PER_BIT) @(posedge clk);
                value[bit_no] = txd;
            end
            repeat (CLKS_PER_BIT) @(posedge clk);
            if (txd !== 1'b1)
                $fatal(1, "UART device stop bit missing");
        end
    endtask

    initial begin
        input_bytes[0] = "1";
        input_bytes[1] = "2";
        input_bytes[2] = " ";
        input_bytes[3] = "3";
        input_bytes[4] = " ";
        input_bytes[5] = "1";
        input_bytes[6] = "0";
        input_bytes[7] = "5";
        input_bytes[8] = " ";
        input_bytes[9] = "1";
        input_bytes[10] = 8'h0d;

        expected_banner[0] = "R";
        expected_banner[1] = "E";
        expected_banner[2] = "A";
        expected_banner[3] = "D";
        expected_banner[4] = "Y";
        expected_banner[5] = 8'h0d;
        expected_banner[6] = 8'h0a;

        // CR LF COUNT:4 CR LF SORTED:1 3 12 105 CR LF
        expected_result[0] = 8'h0d;
        expected_result[1] = 8'h0a;
        expected_result[2] = "C";
        expected_result[3] = "O";
        expected_result[4] = "U";
        expected_result[5] = "N";
        expected_result[6] = "T";
        expected_result[7] = ":";
        expected_result[8] = "4";
        expected_result[9] = 8'h0d;
        expected_result[10] = 8'h0a;
        expected_result[11] = "S";
        expected_result[12] = "O";
        expected_result[13] = "R";
        expected_result[14] = "T";
        expected_result[15] = "E";
        expected_result[16] = "D";
        expected_result[17] = ":";
        expected_result[18] = "1";
        expected_result[19] = " ";
        expected_result[20] = "3";
        expected_result[21] = " ";
        expected_result[22] = "1";
        expected_result[23] = "2";
        expected_result[24] = " ";
        expected_result[25] = "1";
        expected_result[26] = "0";
        expected_result[27] = "5";
        expected_result[28] = 8'h0d;
        expected_result[29] = 8'h0a;

        expected_display[0] = 4;
        expected_display[1] = 1;
        expected_display[2] = 3;
        expected_display[3] = 12;
        expected_display[4] = 105;

        repeat (8) @(negedge clk);
        // Model one short S8 release bounce.  The debounce logic must keep
        // the CPU in reset and produce only the later, complete READY banner.
        rst_n = 1'b1;
        @(negedge clk);
        rst_n = 1'b0;
        repeat (2) @(negedge clk);
        rst_n = 1'b1;

        for (i = 0; i < 7; i = i + 1) begin
            receive_device_byte(received);
            if (received !== expected_banner[i])
                $fatal(1, "banner byte %0d expected %02h, got %02h",
                       i, expected_banner[i], received);
        end

        fork
            begin
                for (i = 0; i < 11; i = i + 1)
                    send_host_byte(input_bytes[i]);
            end
            begin
                for (j = 0; j < 30; j = j + 1) begin
                    receive_device_byte(received);
                    if (received !== expected_result[j])
                        $fatal(1, "result byte %0d expected %02h, got %02h",
                               j, expected_result[j], received);
                end
            end
            begin
                wait (dut.display_sequence_active === 1'b1);
                if (dut.display_sequence_value !== expected_display[0])
                    $fatal(1, "display first frame expected 4, got %0d",
                           dut.display_sequence_value);
                for (k = 1; k < 5; k = k + 1) begin
                    wait (dut.display_sequence_value == expected_display[k]);
                end
            end
        join

        if (dut.display_sequence.write_count !== 5)
            $fatal(1, "display queue expected 5 entries, got %0d",
                   dut.display_sequence.write_count);
        for (i = 0; i < 4; i = i + 1)
            if (dut.gen_pipeline_cpu.cpu.u_dmem.ram[i] !== expected_display[i+1])
                $fatal(1, "sorted RAM mismatch at %0d: got %0d",
                       i, dut.gen_pipeline_cpu.cpu.u_dmem.ram[i]);

        $display("PASS tb_cpu_uart: spaced multi-digit input, dynamic count, UART result and display sequence verified");
        $finish;
    end

    initial begin
        #15000000;
        $fatal(1, "tb_cpu_uart timeout");
    end
endmodule
