`timescale 1ns / 1ps

// EES-338 eight-digit seven-segment driver.
// Unsigned decimal, low eight digits, leading-zero suppression.
// O_led[6:0] and O_led_high[6:0] are {a,b,c,d,e,f,g} and active high.
module LCD_controller #(
    parameter integer SCAN_CYCLES = 100000
)(
    input wire I_clk,
    input wire I_rst_n,
    input wire [31:0] I_data,
    output reg [6:0] O_led,
    output reg [6:0] O_led_high,
    output reg [7:0] O_px,
    output wire [1:0] O_dp
);
    assign O_dp = 2'b00;

    reg [31:0] binary_shift;
    reg [39:0] bcd_work;
    reg [39:0] bcd_adjusted;
    reg [39:0] bcd_next;
    reg [31:0] bcd_latest;
    reg [5:0] bit_count;
    reg converting;
    integer k;
    always @(*) begin
        bcd_adjusted = bcd_work;
        for (k = 0; k < 10; k = k + 1)
            if (bcd_work[k*4 +: 4] >= 5)
                bcd_adjusted[k*4 +: 4] = bcd_work[k*4 +: 4] + 4'd3;
        bcd_next = {bcd_adjusted[38:0], binary_shift[31]};
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            binary_shift <= 0;
            bcd_work <= 0;
            bcd_latest <= 0;
            bit_count <= 0;
            converting <= 0;
        end else if (!converting) begin
            binary_shift <= I_data;
            bcd_work <= 0;
            bit_count <= 0;
            converting <= 1;
        end else begin
            bcd_work <= bcd_next;
            binary_shift <= {binary_shift[30:0], 1'b0};
            if (bit_count == 31) begin
                bcd_latest <= bcd_next[31:0];
                converting <= 0;
            end else begin
                bit_count <= bit_count + 1'b1;
            end
        end
    end

    function [6:0] encode_decimal;
        input [3:0] digit;
        begin
            case (digit)
                0: encode_decimal = 7'b1111110;
                1: encode_decimal = 7'b0110000;
                2: encode_decimal = 7'b1101101;
                3: encode_decimal = 7'b1111001;
                4: encode_decimal = 7'b0110011;
                5: encode_decimal = 7'b1011011;
                6: encode_decimal = 7'b1011111;
                7: encode_decimal = 7'b1110000;
                8: encode_decimal = 7'b1111111;
                9: encode_decimal = 7'b1111011;
                default: encode_decimal = 7'b0000000;
            endcase
        end
    endfunction

    localparam integer COUNT_WIDTH = (SCAN_CYCLES <= 2) ? 1 : $clog2(SCAN_CYCLES);
    reg [COUNT_WIDTH-1:0] scan_counter;
    reg [2:0] scan_digit;
    reg [31:0] bcd_frame;
    reg [7:0] visible;
    reg significant;
    integer j;
    always @(*) begin
        visible = 8'b00000001;
        significant = 0;
        for (j = 7; j >= 0; j = j - 1) begin
            if (bcd_frame[j*4 +: 4] != 0) significant = 1;
            if (significant) visible[j] = 1;
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            scan_counter <= 0;
            scan_digit <= 0;
            bcd_frame <= 0;
            O_led <= 0;
            O_led_high <= 0;
            O_px <= 0;
        end else begin
            if (scan_counter == SCAN_CYCLES - 1) begin
                scan_counter <= 0;
                scan_digit <= scan_digit + 1'b1;
                if (scan_digit == 7) bcd_frame <= bcd_latest;
            end else begin
                scan_counter <= scan_counter + 1'b1;
            end

            // Break before make to prevent ghosting between digits.
            if (scan_counter == 0) O_px <= 0;
            if (scan_counter == 1) begin
                O_led <= 0;
                O_led_high <= 0;
                if (scan_digit < 4)
                    O_led <= encode_decimal(bcd_frame[scan_digit*4 +: 4]);
                else
                    O_led_high <= encode_decimal(bcd_frame[scan_digit*4 +: 4]);
            end
            if (scan_counter == 2)
                O_px <= visible[scan_digit] ? (8'b1 << scan_digit) : 8'b0;
        end
    end
endmodule
