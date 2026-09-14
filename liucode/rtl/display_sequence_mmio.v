`timescale 1ns / 1ps

// Memory-mapped queue for the eight-digit seven-segment display.
// 0x4000_0010 CONTROL: bit0 clear, bit1 start/restart playback
// 0x4000_0014 DATA: append one unsigned 32-bit value
module display_sequence_mmio #(
    parameter integer HOLD_CYCLES = 100000000,
    parameter integer MAX_ENTRIES = 17
)(
    input  wire        clk,
    input  wire        reset,
    input  wire [31:0] bus_addr,
    input  wire [31:0] bus_wdata,
    input  wire        bus_write,
    output reg  [31:0] display_value,
    output reg         active
);
    localparam [31:0] DISPLAY_CONTROL = 32'h4000_0010;
    localparam [31:0] DISPLAY_DATA    = 32'h4000_0014;
    localparam integer HOLD_COUNT_WIDTH =
        (HOLD_CYCLES <= 2) ? 1 : $clog2(HOLD_CYCLES);
    localparam integer ENTRY_COUNT_WIDTH =
        (MAX_ENTRIES <= 2) ? 1 : $clog2(MAX_ENTRIES + 1);

    reg [31:0] entries [0:MAX_ENTRIES-1];
    reg [ENTRY_COUNT_WIDTH-1:0] write_count;
    reg [ENTRY_COUNT_WIDTH-1:0] playback_index;
    reg [HOLD_COUNT_WIDTH-1:0] hold_counter;

    wire clear_command = bus_write && (bus_addr == DISPLAY_CONTROL) &&
                         bus_wdata[0];
    wire start_command = bus_write && (bus_addr == DISPLAY_CONTROL) &&
                         bus_wdata[1];
    wire append_value  = bus_write && (bus_addr == DISPLAY_DATA);

    always @(posedge clk) begin
        if (reset) begin
            display_value <= 32'b0;
            active <= 1'b0;
            write_count <= 0;
            playback_index <= 0;
            hold_counter <= 0;
        end else if (clear_command) begin
            display_value <= 32'b0;
            active <= 1'b0;
            write_count <= 0;
            playback_index <= 0;
            hold_counter <= 0;
        end else begin
            if (append_value && write_count < MAX_ENTRIES) begin
                entries[write_count] <= bus_wdata;
                write_count <= write_count + 1'b1;
            end

            if (start_command && write_count != 0) begin
                display_value <= entries[0];
                active <= 1'b1;
                playback_index <= 0;
                hold_counter <= 0;
            end else if (active) begin
                if (hold_counter == HOLD_CYCLES - 1) begin
                    hold_counter <= 0;
                    if (playback_index + 1'b1 >= write_count) begin
                        playback_index <= 0;
                        display_value <= entries[0];
                    end else begin
                        playback_index <= playback_index + 1'b1;
                        display_value <= entries[playback_index + 1'b1];
                    end
                end else begin
                    hold_counter <= hold_counter + 1'b1;
                end
            end
        end
    end
endmodule
