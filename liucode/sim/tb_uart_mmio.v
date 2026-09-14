`timescale 1ns / 1ps

// Fast self-check for the UART IP.  A short simulated clock/baud ratio keeps
// runtime small while exercising the same state machines used at 100 MHz.
module tb_uart_mmio;
    localparam integer CLOCK_FREQ_HZ = 1_000_000;
    localparam integer BAUD_RATE = 100_000;
    localparam integer CLKS_PER_BIT = CLOCK_FREQ_HZ / BAUD_RATE;

    reg clk = 1'b0;
    reg reset = 1'b1;
    reg serial_rx = 1'b1;
    wire serial_tx;
    reg [31:0] bus_addr = 0;
    reg [31:0] bus_wdata = 0;
    reg bus_write = 0;
    reg bus_read = 0;
    wire [31:0] bus_rdata;
    wire rx_valid;
    wire tx_busy;
    integer i;
    reg [7:0] sampled_tx;

    always #5 clk = ~clk;

    uart_mmio #(
        .CLOCK_FREQ_HZ(CLOCK_FREQ_HZ),
        .BAUD_RATE(BAUD_RATE)
    ) dut (
        .clk(clk), .reset(reset),
        .uart_rx(serial_rx), .uart_tx(serial_tx),
        .bus_addr(bus_addr), .bus_wdata(bus_wdata),
        .bus_write(bus_write), .bus_read(bus_read),
        .bus_rdata(bus_rdata),
        .rx_valid_debug(rx_valid), .tx_busy_debug(tx_busy)
    );

    task send_rx_byte;
        input [7:0] value;
        integer bit_no;
        begin
            @(negedge clk);
            serial_rx = 1'b0;
            repeat (CLKS_PER_BIT) @(negedge clk);
            for (bit_no = 0; bit_no < 8; bit_no = bit_no + 1) begin
                serial_rx = value[bit_no];
                repeat (CLKS_PER_BIT) @(negedge clk);
            end
            serial_rx = 1'b1;
            repeat (CLKS_PER_BIT) @(negedge clk);
        end
    endtask

    task write_bus;
        input [31:0] address;
        input [31:0] value;
        begin
            @(negedge clk);
            bus_addr = address;
            bus_wdata = value;
            bus_write = 1'b1;
            @(negedge clk);
            bus_write = 1'b0;
        end
    endtask

    task read_rx_data;
        output [7:0] value;
        begin
            @(negedge clk);
            bus_addr = 32'h4000_0004;
            bus_read = 1'b1;
            #1;
            value = bus_rdata[7:0];
            @(negedge clk);
            bus_read = 1'b0;
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        reset = 1'b0;

        // RX path and read-to-clear behaviour.
        send_rx_byte(8'hA6);
        wait (rx_valid);
        bus_addr = 32'h4000_0008;
        #1;
        if (!bus_rdata[0])
            $fatal(1, "UART RX_VALID did not assert");
        read_rx_data(sampled_tx);
        if (sampled_tx !== 8'hA6)
            $fatal(1, "UART RX expected A6, got %02h", sampled_tx);
        @(posedge clk);
        if (rx_valid)
            $fatal(1, "UART RX_VALID did not clear after RXDATA read");

        // TX path.  Sample at the centre of every transmitted bit.
        write_bus(32'h4000_0000, 32'h0000_005A);
        wait (serial_tx == 1'b0);
        repeat (CLKS_PER_BIT / 2) @(posedge clk);
        if (serial_tx !== 1'b0)
            $fatal(1, "UART TX start bit missing");
        for (i = 0; i < 8; i = i + 1) begin
            repeat (CLKS_PER_BIT) @(posedge clk);
            sampled_tx[i] = serial_tx;
        end
        repeat (CLKS_PER_BIT) @(posedge clk);
        if (serial_tx !== 1'b1)
            $fatal(1, "UART TX stop bit missing");
        if (sampled_tx !== 8'h5A)
            $fatal(1, "UART TX expected 5A, got %02h", sampled_tx);
        wait (!tx_busy);

        // A write while busy must be reported, not silently accepted.
        write_bus(32'h4000_0000, 32'h0000_0033);
        write_bus(32'h4000_0000, 32'h0000_0044);
        bus_addr = 32'h4000_0008;
        #1;
        if (!bus_rdata[5])
            $fatal(1, "UART TX_DROPPED status did not assert");
        write_bus(32'h4000_000c, 32'h1);
        bus_addr = 32'h4000_0008;
        #1;
        if (bus_rdata[5:3] !== 3'b000)
            $fatal(1, "UART sticky error flags did not clear");

        $display("PASS tb_uart_mmio: RX, TX, status and error handling verified");
        $finish;
    end

    initial begin
        #200000;
        $fatal(1, "tb_uart_mmio timeout");
    end
endmodule
