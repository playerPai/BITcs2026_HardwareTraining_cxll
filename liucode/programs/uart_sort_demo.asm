# UART + pipelined CPU integration demo, line-oriented edition.
#
# Terminal: 115200 baud, 8N1, ASCII. Enter up to 16 unsigned decimal
# integers separated by spaces, then send CR or LF. Display range: 0..99999999.
# Example: 12 3 105 1<Enter> -> COUNT:4 / SORTED:1 3 12 105
#
# UART MMIO: 0x40000000 TX, 0x40000004 RX, 0x40000008 STATUS
# Display:   0x40000010 CONTROL, 0x40000014 DATA

start:
    lui  x20, 0x40000
    addi x5, x0, 82
    jal  x1, putc
    addi x5, x0, 69
    jal  x1, putc
    addi x5, x0, 65
    jal  x1, putc
    addi x5, x0, 68
    jal  x1, putc
    addi x5, x0, 89
    jal  x1, putc
    addi x5, x0, 13
    jal  x1, putc
    addi x5, x0, 10
    jal  x1, putc

    addi x21, x0, 0             # next array address
    addi x22, x0, 0             # stored number count
    addi x23, x0, 0             # current multi-digit value
    addi x24, x0, 0             # currently inside a number
    addi x25, x0, 16            # maximum count

receive_loop:
    jal  x1, getc
    addi x6, x0, 13
    beq  x5, x6, line_end
    addi x6, x0, 10
    beq  x5, x6, line_end
    addi x6, x0, 32
    beq  x5, x6, delimiter
    addi x6, x0, 48             # ignore non-digits
    blt  x5, x6, receive_loop
    addi x6, x0, 58
    bge  x5, x6, receive_loop
    bge  x22, x25, receive_loop # ignore values after the 16th
    addi x5, x5, -48
    addi x24, x0, 1
    add  x8, x23, x23           # current = current * 10 + digit
    add  x9, x8, x8
    add  x9, x9, x9
    add  x23, x9, x8
    add  x23, x23, x5
    beq  x0, x0, receive_loop

delimiter:
    beq  x24, x0, receive_loop  # accept repeated spaces
    sw   x23, 0(x21)
    addi x21, x21, 4
    addi x22, x22, 1
    addi x23, x0, 0
    addi x24, x0, 0
    beq  x0, x0, receive_loop

line_end:
    beq  x24, x0, parse_done
    bge  x22, x25, parse_done
    sw   x23, 0(x21)
    addi x22, x22, 1
    addi x23, x0, 0
    addi x24, x0, 0

parse_done:
    beq  x22, x0, receive_loop
    addi x24, x22, -1
    beq  x24, x0, sorted

sort_outer:
    addi x21, x0, 0
    add  x23, x24, x0
sort_inner:
    lw   x6, 0(x21)
    lw   x7, 4(x21)
    bge  x7, x6, no_swap
    sw   x7, 0(x21)
    sw   x6, 4(x21)
no_swap:
    addi x21, x21, 4
    addi x23, x23, -1
    bne  x23, x0, sort_inner
    addi x24, x24, -1
    bne  x24, x0, sort_outer

sorted:
    # Decimal divisors for print_uint, away from the value array.
    lui  x6, 0x989
    addi x6, x6, 1664           # 10000000
    sw   x6, 128(x0)
    lui  x6, 0x0f4
    addi x6, x6, 576            # 1000000
    sw   x6, 132(x0)
    lui  x6, 0x018
    addi x6, x6, 1696           # 100000
    sw   x6, 136(x0)
    lui  x6, 0x002
    addi x6, x6, 1808           # 10000
    sw   x6, 140(x0)
    addi x6, x0, 1000
    sw   x6, 144(x0)
    addi x6, x0, 100
    sw   x6, 148(x0)
    addi x6, x0, 10
    sw   x6, 152(x0)
    addi x6, x0, 1
    sw   x6, 156(x0)

    addi x5, x0, 13             # CR LF COUNT:
    jal  x1, putc
    addi x5, x0, 10
    jal  x1, putc
    addi x5, x0, 67
    jal  x1, putc
    addi x5, x0, 79
    jal  x1, putc
    addi x5, x0, 85
    jal  x1, putc
    addi x5, x0, 78
    jal  x1, putc
    addi x5, x0, 84
    jal  x1, putc
    addi x5, x0, 58
    jal  x1, putc
    add  x5, x22, x0
    jal  x28, print_uint

    addi x5, x0, 13             # CR LF SORTED:
    jal  x1, putc
    addi x5, x0, 10
    jal  x1, putc
    addi x5, x0, 83
    jal  x1, putc
    addi x5, x0, 79
    jal  x1, putc
    addi x5, x0, 82
    jal  x1, putc
    addi x5, x0, 84
    jal  x1, putc
    addi x5, x0, 69
    jal  x1, putc
    addi x5, x0, 68
    jal  x1, putc
    addi x5, x0, 58
    jal  x1, putc

    addi x21, x0, 0
    add  x24, x22, x0
    addi x26, x0, 0
send_loop:
    beq  x26, x0, no_space
    addi x5, x0, 32
    jal  x1, putc
no_space:
    lw   x5, 0(x21)
    jal  x28, print_uint
    addi x21, x21, 4
    addi x24, x24, -1
    addi x26, x26, 1
    bne  x24, x0, send_loop
    addi x5, x0, 13
    jal  x1, putc
    addi x5, x0, 10
    jal  x1, putc

    # Queue count first, then sorted numbers, and start looping.
    addi x5, x0, 1
    sw   x5, 16(x20)
    sw   x22, 20(x20)
    addi x21, x0, 0
    add  x24, x22, x0
display_fill_loop:
    lw   x5, 0(x21)
    sw   x5, 20(x20)
    addi x21, x21, 4
    addi x24, x24, -1
    bne  x24, x0, display_fill_loop
    addi x5, x0, 2
    sw   x5, 16(x20)

done:
    beq  x0, x0, done

# print_uint: print x5 without leading zeros; return through x28.
print_uint:
    addi x8, x0, 128
    addi x9, x0, 8
    addi x10, x0, 0
print_digit:
    lw   x11, 0(x8)
    addi x12, x0, 0
print_subtract:
    blt  x5, x11, print_emit_check
    sub  x5, x5, x11
    addi x12, x12, 1
    beq  x0, x0, print_subtract
print_emit_check:
    bne  x12, x0, print_emit
    bne  x10, x0, print_emit
    addi x6, x0, 1
    bne  x11, x6, print_advance
print_emit:
    add  x13, x5, x0
    addi x5, x12, 48
    jal  x1, putc
    add  x5, x13, x0
    addi x10, x0, 1
print_advance:
    addi x8, x8, 4
    addi x9, x9, -1
    bne  x9, x0, print_digit
    jalr x0, 0(x28)

putc:
putc_wait:
    lw   x6, 8(x20)
    andi x6, x6, 2
    beq  x6, x0, putc_wait
    sw   x5, 0(x20)
    jalr x0, 0(x1)

getc:
getc_wait:
    lw   x6, 8(x20)
    andi x6, x6, 1
    beq  x6, x0, getc_wait
    lw   x5, 4(x20)
    jalr x0, 0(x1)
