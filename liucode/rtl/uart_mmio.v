`timescale 1ns / 1ps

// Memory-mapped full-duplex UART for the EES-338 on-board USB serial port.
//
// Address map (word accesses):
//   0x4000_0000 TXDATA  W: low byte starts a transmission when TX_READY=1
//   0x4000_0004 RXDATA  R: low byte is received data; the read clears RX_VALID
//   0x4000_0008 STATUS  R: bit0 RX_VALID, bit1 TX_READY, bit2 TX_BUSY,
//                            bit3 RX_OVERRUN, bit4 FRAME_ERROR, bit5 TX_DROPPED
//   0x4000_000c CONTROL W: writing bit0 clears sticky error flags
//
// The peripheral itself always runs from the board clock.  CPU clock-enable
// stepping must therefore be disabled (CPU_STEP_CYCLES=1) for interactive use.
module uart_mmio #(
    parameter integer CLOCK_FREQ_HZ = 100_000_000,
    parameter integer BAUD_RATE     = 115_200
)(
    input  wire        clk,
    input  wire        reset,
    input  wire        uart_rx,
    output wire        uart_tx,

    input  wire [31:0] bus_addr,
    input  wire [31:0] bus_wdata,
    input  wire        bus_write,
    input  wire        bus_read,
    output reg  [31:0] bus_rdata,

    output wire        rx_valid_debug,
    output wire        tx_busy_debug
);
    localparam [31:0] UART_TXDATA  = 32'h4000_0000;
    localparam [31:0] UART_RXDATA  = 32'h4000_0004;
    localparam [31:0] UART_STATUS  = 32'h4000_0008;
    localparam [31:0] UART_CONTROL = 32'h4000_000c;

    wire [7:0] rx_byte;
    wire       rx_byte_valid;
    wire       rx_frame_error;
    reg  [7:0] rx_data_reg;
    reg        rx_valid_reg;
    reg        rx_overrun_reg;
    reg        frame_error_reg;
    reg        tx_dropped_reg;

    wire       tx_ready;
    wire       tx_busy;
    wire       tx_start = bus_write && (bus_addr == UART_TXDATA) && tx_ready;
    wire       rx_read  = bus_read  && (bus_addr == UART_RXDATA);
    wire       clear_errors = bus_write && (bus_addr == UART_CONTROL) &&
                              bus_wdata[0];

    uart_rx_8n1 #(
        .CLOCK_FREQ_HZ(CLOCK_FREQ_HZ),
        .BAUD_RATE(BAUD_RATE)
    ) u_rx (
        .clk(clk), .reset(reset), .rx(uart_rx),
        .data(rx_byte), .data_valid(rx_byte_valid),
        .frame_error(rx_frame_error)
    );

    uart_tx_8n1 #(
        .CLOCK_FREQ_HZ(CLOCK_FREQ_HZ),
        .BAUD_RATE(BAUD_RATE)
    ) u_tx (
        .clk(clk), .reset(reset), .start(tx_start),
        .data(bus_wdata[7:0]), .tx(uart_tx),
        .busy(tx_busy), .ready(tx_ready)
    );

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            rx_data_reg     <= 8'b0;
            rx_valid_reg    <= 1'b0;
            rx_overrun_reg  <= 1'b0;
            frame_error_reg <= 1'b0;
            tx_dropped_reg  <= 1'b0;
        end else begin
            if (rx_read)
                rx_valid_reg <= 1'b0;

            // A newly completed byte has priority over a simultaneous read.
            if (rx_byte_valid) begin
                if (rx_valid_reg && !rx_read)
                    rx_overrun_reg <= 1'b1;
                rx_data_reg  <= rx_byte;
                rx_valid_reg <= 1'b1;
            end

            if (rx_frame_error)
                frame_error_reg <= 1'b1;

            if (bus_write && (bus_addr == UART_TXDATA) && !tx_ready)
                tx_dropped_reg <= 1'b1;

            if (clear_errors) begin
                rx_overrun_reg  <= 1'b0;
                frame_error_reg <= 1'b0;
                tx_dropped_reg  <= 1'b0;
            end
        end
    end

    always @(*) begin
        case (bus_addr)
            UART_RXDATA: bus_rdata = {24'b0, rx_data_reg};
            UART_STATUS: bus_rdata = {26'b0, tx_dropped_reg,
                                      frame_error_reg, rx_overrun_reg,
                                      tx_busy, tx_ready, rx_valid_reg};
            default:     bus_rdata = 32'b0;
        endcase
    end

    assign rx_valid_debug = rx_valid_reg;
    assign tx_busy_debug  = tx_busy;
endmodule


// 8 data bits, no parity, one stop bit.  The asynchronous RX input is first
// passed through a two-flop synchronizer, then sampled near each bit centre.
module uart_rx_8n1 #(
    parameter integer CLOCK_FREQ_HZ = 100_000_000,
    parameter integer BAUD_RATE     = 115_200
)(
    input  wire       clk,
    input  wire       reset,
    input  wire       rx,
    output reg  [7:0] data,
    output reg        data_valid,
    output reg        frame_error
);
    localparam integer CLKS_PER_BIT_RAW = CLOCK_FREQ_HZ / BAUD_RATE;
    localparam integer CLKS_PER_BIT = (CLKS_PER_BIT_RAW < 4) ? 4
                                                              : CLKS_PER_BIT_RAW;
    localparam integer COUNT_WIDTH = (CLKS_PER_BIT <= 2) ? 1
                                                         : $clog2(CLKS_PER_BIT);
    localparam [1:0] RX_IDLE  = 2'd0;
    localparam [1:0] RX_START = 2'd1;
    localparam [1:0] RX_DATA  = 2'd2;
    localparam [1:0] RX_STOP  = 2'd3;

    (* ASYNC_REG = "TRUE" *) reg [1:0] rx_sync_pipe;
    reg [1:0] state;
    reg [COUNT_WIDTH-1:0] count;
    reg [2:0] bit_index;
    reg [7:0] shift_reg;
    wire rx_sync = rx_sync_pipe[1];

    always @(posedge clk or posedge reset) begin
        if (reset)
            rx_sync_pipe <= 2'b11;
        else
            rx_sync_pipe <= {rx_sync_pipe[0], rx};
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state       <= RX_IDLE;
            count       <= 0;
            bit_index   <= 0;
            shift_reg   <= 0;
            data        <= 0;
            data_valid  <= 1'b0;
            frame_error <= 1'b0;
        end else begin
            data_valid  <= 1'b0;
            frame_error <= 1'b0;
            case (state)
                RX_IDLE: begin
                    count <= 0;
                    if (!rx_sync)
                        state <= RX_START;
                end

                RX_START: begin
                    if (count == (CLKS_PER_BIT / 2) - 1) begin
                        count <= 0;
                        if (!rx_sync) begin
                            bit_index <= 0;
                            state <= RX_DATA;
                        end else begin
                            state <= RX_IDLE;
                        end
                    end else begin
                        count <= count + 1'b1;
                    end
                end

                RX_DATA: begin
                    if (count == CLKS_PER_BIT - 1) begin
                        count <= 0;
                        shift_reg[bit_index] <= rx_sync;
                        if (bit_index == 3'd7)
                            state <= RX_STOP;
                        else
                            bit_index <= bit_index + 1'b1;
                    end else begin
                        count <= count + 1'b1;
                    end
                end

                RX_STOP: begin
                    if (count == CLKS_PER_BIT - 1) begin
                        count <= 0;
                        state <= RX_IDLE;
                        if (rx_sync) begin
                            data <= shift_reg;
                            data_valid <= 1'b1;
                        end else begin
                            frame_error <= 1'b1;
                        end
                    end else begin
                        count <= count + 1'b1;
                    end
                end

                default: state <= RX_IDLE;
            endcase
        end
    end
endmodule


module uart_tx_8n1 #(
    parameter integer CLOCK_FREQ_HZ = 100_000_000,
    parameter integer BAUD_RATE     = 115_200
)(
    input  wire       clk,
    input  wire       reset,
    input  wire       start,
    input  wire [7:0] data,
    output reg        tx,
    output reg        busy,
    output wire       ready
);
    localparam integer CLKS_PER_BIT_RAW = CLOCK_FREQ_HZ / BAUD_RATE;
    localparam integer CLKS_PER_BIT = (CLKS_PER_BIT_RAW < 4) ? 4
                                                              : CLKS_PER_BIT_RAW;
    localparam integer COUNT_WIDTH = (CLKS_PER_BIT <= 2) ? 1
                                                         : $clog2(CLKS_PER_BIT);
    reg [COUNT_WIDTH-1:0] count;
    reg [3:0] bit_index;
    reg [9:0] frame;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            tx        <= 1'b1;
            busy      <= 1'b0;
            count     <= 0;
            bit_index <= 0;
            frame     <= 10'h3ff;
        end else if (!busy) begin
            tx    <= 1'b1;
            count <= 0;
            if (start) begin
                frame     <= {1'b1, data, 1'b0};
                tx        <= 1'b0;
                busy      <= 1'b1;
                bit_index <= 0;
            end
        end else begin
            if (count == CLKS_PER_BIT - 1) begin
                count <= 0;
                if (bit_index == 4'd9) begin
                    tx   <= 1'b1;
                    busy <= 1'b0;
                end else begin
                    bit_index <= bit_index + 1'b1;
                    tx <= frame[bit_index + 1'b1];
                end
            end else begin
                count <= count + 1'b1;
            end
        end
    end

    assign ready = !busy;
endmodule
